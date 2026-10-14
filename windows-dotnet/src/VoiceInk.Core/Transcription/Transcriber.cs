using System.Net.Http.Headers;
using System.Text.Json.Nodes;
using VoiceInk.Core.Config;

namespace VoiceInk.Core.Transcription;

public sealed class TranscriptionException(string message, Exception? inner = null) : Exception(message, inner);

public sealed record TranscriptionRequest(
    byte[] Wav,
    float[] Samples,
    string? Language,
    IReadOnlyList<string> Vocabulary);

public static class Transcriber
{
    /// <summary>Runs the configured provider and returns the trimmed transcript (never empty).</summary>
    public static async Task<string> TranscribeAsync(
        TranscriptionSettings settings, TranscriptionRequest request, CancellationToken ct)
    {
        var provider = settings.Provider;
        var model = settings.ModelName;
        var timeout = TimeSpan.FromSeconds(Math.Max(10, (long)settings.TimeoutSecs));

        string ApiKey() => Credentials.Get(provider.KeyName())
            ?? throw new TranscriptionException($"no API key configured for {provider.DisplayName()}");

        string text;
        try
        {
            text = provider switch
            {
                TranscriptionProvider.Groq => await CloudProviders.OpenAiCompatibleAsync(
                    "https://api.groq.com/openai/v1/audio/transcriptions", ApiKey(), model, request, timeout, ct),
                TranscriptionProvider.OpenAI => await CloudProviders.OpenAiCompatibleAsync(
                    "https://api.openai.com/v1/audio/transcriptions", ApiKey(), model, request, timeout, ct),
                TranscriptionProvider.Mistral => await CloudProviders.OpenAiCompatibleAsync(
                    "https://api.mistral.ai/v1/audio/transcriptions", ApiKey(), model, request, timeout, ct),
                TranscriptionProvider.Custom => await CustomAsync(settings, model, request, timeout, ct),
                TranscriptionProvider.Deepgram => await CloudProviders.DeepgramAsync(ApiKey(), model, request, timeout, ct),
                TranscriptionProvider.ElevenLabs => await CloudProviders.ElevenLabsAsync(ApiKey(), model, request, timeout, ct),
                TranscriptionProvider.Local => await LocalTranscribeAsync(settings, model, request, ct),
                _ => throw new TranscriptionException("unknown transcription provider"),
            };
        }
        catch (HttpFailure e)
        {
            throw new TranscriptionException(e.Message, e);
        }

        text = text.Trim();
        return text.Length == 0 ? throw new TranscriptionException("the provider returned no transcript") : text;
    }

    private static Task<string> CustomAsync(
        TranscriptionSettings settings, string model, TranscriptionRequest request, TimeSpan timeout, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(settings.CustomEndpoint))
        {
            throw new TranscriptionException("set the custom endpoint in Settings › Transcription");
        }

        return CloudProviders.OpenAiCompatibleAsync(
            settings.CustomEndpoint.Trim(), Credentials.Get(settings.Provider.KeyName()), model, request, timeout, ct);
    }

    private static async Task<string> LocalTranscribeAsync(
        TranscriptionSettings settings, string model, TranscriptionRequest request, CancellationToken ct)
    {
        var path = Path.Combine(settings.ResolvedModelsDir, model);
        try
        {
            return await LocalWhisper.TranscribeAsync(path, request.Samples, request.Language, request.Vocabulary, ct);
        }
        catch (FileNotFoundException e)
        {
            throw new TranscriptionException(e.Message, e);
        }
        catch (Exception e) when (e is not OperationCanceledException and not TranscriptionException)
        {
            throw new TranscriptionException($"local transcription failed: {e.Message}", e);
        }
    }
}

internal static class CloudProviders
{
    internal static string? VocabularyPrompt(IReadOnlyList<string> vocabulary)
    {
        var words = vocabulary.Select(w => w.Trim()).Where(w => w.Length > 0);
        var prompt = new System.Text.StringBuilder();
        foreach (var w in words)
        {
            if (prompt.Length + w.Length + 2 > 600) break;
            if (prompt.Length > 0) prompt.Append(", ");
            prompt.Append(w);
        }

        return prompt.Length == 0 ? null : prompt.ToString();
    }

    private static string TextField(JsonNode json) =>
        json["text"]?.GetValue<string>() ?? throw new TranscriptionException("the provider returned no transcript");

    private static ByteArrayContent WavContent(byte[] wav, string contentType = "audio/wav")
    {
        var content = new ByteArrayContent(wav);
        content.Headers.ContentType = MediaTypeHeaderValue.Parse(contentType);
        return content;
    }

    public static async Task<string> OpenAiCompatibleAsync(
        string endpoint, string? apiKey, string model, TranscriptionRequest request, TimeSpan timeout, CancellationToken ct)
    {
        var form = new MultipartFormDataContent
        {
            { WavContent(request.Wav), "file", "audio.wav" },
            { new StringContent(model), "model" },
            { new StringContent("json"), "response_format" },
            { new StringContent("0"), "temperature" },
        };
        if (request.Language is { } lang) form.Add(new StringContent(lang), "language");
        if (VocabularyPrompt(request.Vocabulary) is { } prompt) form.Add(new StringContent(prompt), "prompt");

        using var message = new HttpRequestMessage(HttpMethod.Post, endpoint) { Content = form };
        if (!string.IsNullOrEmpty(apiKey)) message.Headers.TryAddWithoutValidation("Authorization", $"Bearer {apiKey}");
        return TextField(await Http.SendJsonAsync(message, timeout, ct));
    }

    public static async Task<string> DeepgramAsync(
        string apiKey, string model, TranscriptionRequest request, TimeSpan timeout, CancellationToken ct)
    {
        var language = request.Language ?? (model == "nova-3" ? "multi" : "en");
        var url = new System.Text.StringBuilder(
            $"https://api.deepgram.com/v1/listen?model={Http.UrlEncode(model)}&smart_format=true&punctuate=true&language={Http.UrlEncode(language)}");
        foreach (var term in request.Vocabulary.Select(t => t.Trim()).Where(t => t.Length > 0).Take(100))
        {
            url.Append("&keyterm=").Append(Http.UrlEncode(term));
        }

        using var message = new HttpRequestMessage(HttpMethod.Post, url.ToString()) { Content = WavContent(request.Wav) };
        message.Headers.TryAddWithoutValidation("Authorization", $"Token {apiKey}");
        var json = await Http.SendJsonAsync(message, timeout, ct);
        return json["results"]?["channels"]?[0]?["alternatives"]?[0]?["transcript"]?.GetValue<string>()
            ?? throw new TranscriptionException("the provider returned no transcript");
    }

    public static async Task<string> ElevenLabsAsync(
        string apiKey, string model, TranscriptionRequest request, TimeSpan timeout, CancellationToken ct)
    {
        var form = new MultipartFormDataContent
        {
            { WavContent(request.Wav), "file", "audio.wav" },
            { new StringContent(model), "model_id" },
            { new StringContent("false"), "tag_audio_events" },
        };
        if (request.Language is { } lang) form.Add(new StringContent(lang), "language_code");

        using var message = new HttpRequestMessage(HttpMethod.Post, "https://api.elevenlabs.io/v1/speech-to-text") { Content = form };
        message.Headers.TryAddWithoutValidation("xi-api-key", apiKey);
        return TextField(await Http.SendJsonAsync(message, timeout, ct));
    }
}
