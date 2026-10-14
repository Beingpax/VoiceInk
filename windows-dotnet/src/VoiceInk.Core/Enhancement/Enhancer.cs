using System.Diagnostics;
using System.Text.Json.Nodes;
using VoiceInk.Core.Config;
using VoiceInk.Core.Text;

namespace VoiceInk.Core.Enhancement;

public sealed class EnhancementException(string message, Exception? inner = null) : Exception(message, inner)
{
    public static EnhancementException Empty() => new("AI enhancement failed to process the text.");
}

public sealed record EnhancementResult(
    string Text,
    TimeSpan Duration,
    string PromptName,
    string Model,
    string SystemMessage,
    string UserMessage);

public sealed record EnhancementRequest(
    EnhancementSettings Settings,
    EnhancementProvider Provider,
    string Model,
    CustomPrompt Prompt,
    PromptContext Context);

/// <summary>LLM clean-up of transcripts and Command Mode, with the macOS app's retry, backoff and rate limit.</summary>
public static class Enhancer
{
    private static readonly object RateGate = new();
    private static DateTime _lastRequest = DateTime.MinValue;
    private static readonly TimeSpan RateLimitInterval = TimeSpan.FromSeconds(1);

    /// <summary>Test hook: replaces <see cref="Task.Delay(TimeSpan, CancellationToken)"/> for retries.</summary>
    internal static Func<TimeSpan, CancellationToken, Task> Delay { get; set; } = Task.Delay;

    public static bool IsConfigured(EnhancementSettings settings, EnhancementProvider provider) => provider switch
    {
        EnhancementProvider.Ollama => true,
        EnhancementProvider.Custom => !string.IsNullOrWhiteSpace(settings.CustomEndpoint),
        var p => Credentials.Has(p.KeyName()),
    };

    private static async Task WaitForRateLimitAsync(CancellationToken ct)
    {
        TimeSpan wait;
        lock (RateGate)
        {
            var elapsed = DateTime.UtcNow - _lastRequest;
            wait = elapsed < RateLimitInterval ? RateLimitInterval - elapsed : TimeSpan.Zero;
            _lastRequest = DateTime.UtcNow + wait;
        }

        if (wait > TimeSpan.Zero) await Delay(wait, ct).ConfigureAwait(false);
    }

    public static async Task<EnhancementResult> EnhanceAsync(string text, EnhancementRequest req, CancellationToken ct)
    {
        var system = PromptTemplates.BuildSystemMessage(req.Prompt, req.Context);
        var user = PromptTemplates.BuildUserMessage(text);
        if (string.IsNullOrWhiteSpace(text))
        {
            return new EnhancementResult("", TimeSpan.Zero, req.Prompt.Title, req.Model, system, user);
        }

        return await CompleteMessagesAsync(req.Settings, req.Provider, req.Model, req.Prompt.Title, system, user, ct)
            .ConfigureAwait(false);
    }

    /// <summary>Sends one system+user message pair, retrying transient failures.</summary>
    public static async Task<EnhancementResult> CompleteMessagesAsync(
        EnhancementSettings settings, EnhancementProvider provider, string model, string promptName,
        string system, string user, CancellationToken ct)
    {
        var clock = Stopwatch.StartNew();
        if (!IsConfigured(settings, provider))
        {
            throw new EnhancementException($"no API key configured for {provider.DisplayName()}");
        }

        var maxAttempts = Math.Max(1u, settings.MaxAttempts);
        var delay = TimeSpan.FromSeconds(1);
        var attempt = 0u;
        string output;
        while (true)
        {
            attempt++;
            if (provider.IsRateLimited()) await WaitForRateLimitAsync(ct).ConfigureAwait(false);
            try
            {
                output = await CompleteAsync(settings, provider, model, system, user, ct).ConfigureAwait(false);
                break;
            }
            catch (HttpFailure e) when (attempt < maxAttempts && e.IsTransient)
            {
                await Delay(delay, ct).ConfigureAwait(false);
                delay *= 2;
            }
            catch (HttpFailure e) when (attempt < maxAttempts && e.Kind == HttpErrorKind.Timeout && settings.RetryOnTimeout)
            {
                // Retry immediately; the request itself already waited.
            }
            catch (HttpFailure e)
            {
                throw new EnhancementException(e.Message, e);
            }
        }

        var filtered = TextFilter.FilterEnhancementOutput(output.Trim());
        if (filtered.Length == 0 && provider != EnhancementProvider.Ollama)
        {
            throw EnhancementException.Empty();
        }

        return new EnhancementResult(filtered, clock.Elapsed, promptName, model, system, user);
    }

    private static async Task<string> CompleteAsync(
        EnhancementSettings settings, EnhancementProvider provider, string model, string system, string user,
        CancellationToken ct)
    {
        var timeout = TimeSpan.FromSeconds(Math.Max(5, (long)settings.TimeoutSecs));
        var endpoint = settings.EndpointFor(provider);

        if (provider == EnhancementProvider.Anthropic)
        {
            using var message = Http.JsonRequest(endpoint, AnthropicBody(model, system, user));
            message.Headers.TryAddWithoutValidation("x-api-key", Credentials.Get(provider.KeyName()) ?? "");
            message.Headers.TryAddWithoutValidation("anthropic-version", "2023-06-01");
            var json = await Http.SendJsonAsync(message, timeout, ct).ConfigureAwait(false);
            return ParseAnthropic(json) ?? throw EnhancementException.Empty();
        }
        else
        {
            using var message = Http.JsonRequest(endpoint, OpenAiBody(provider, model, system, user));
            if (Credentials.Get(provider.KeyName()) is { } key)
            {
                message.Headers.TryAddWithoutValidation("Authorization", $"Bearer {key}");
            }

            if (provider == EnhancementProvider.OpenRouter)
            {
                message.Headers.TryAddWithoutValidation("HTTP-Referer", "https://tryvoiceink.com");
                message.Headers.TryAddWithoutValidation("X-Title", "VoiceInk");
            }

            var json = await Http.SendJsonAsync(message, timeout, ct).ConfigureAwait(false);
            return ParseOpenAi(json) ?? throw EnhancementException.Empty();
        }
    }

    internal static JsonObject OpenAiBody(EnhancementProvider provider, string model, string system, string user)
    {
        var body = new JsonObject
        {
            ["model"] = model,
            ["messages"] = new JsonArray(
                new JsonObject { ["role"] = "system", ["content"] = system },
                new JsonObject { ["role"] = "user", ["content"] = user }),
            ["stream"] = false,
        };
        // Reasoning-capable OpenAI models reject `temperature`; everyone else gets a low one.
        if (provider != EnhancementProvider.OpenAI) body["temperature"] = 0.3;
        return body;
    }

    internal static JsonObject AnthropicBody(string model, string system, string user) => new()
    {
        ["model"] = model,
        ["max_tokens"] = 8192,
        ["system"] = system,
        ["messages"] = new JsonArray(new JsonObject { ["role"] = "user", ["content"] = user }),
    };

    internal static string? ParseOpenAi(JsonNode json)
    {
        var content = json["choices"]?[0]?["message"]?["content"];
        return content switch
        {
            JsonValue v when v.TryGetValue<string>(out var s) => s,
            // Some servers return content parts.
            JsonArray parts => string.Concat(parts.Select(p => p?["text"]?.GetValue<string>())),
            _ => null,
        };
    }

    internal static string? ParseAnthropic(JsonNode json)
    {
        if (json["content"] is not JsonArray blocks) return null;
        return string.Concat(blocks
            .Where(b => b?["type"]?.GetValue<string>() == "text")
            .Select(b => b?["text"]?.GetValue<string>()));
    }
}
