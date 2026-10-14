using System.Net;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace VoiceInk.Core;

public enum HttpErrorKind { Status, Timeout, Network, Decode }

/// <summary>A failed HTTP request, with the same friendly messages as the Rust version.</summary>
public sealed class HttpFailure : Exception
{
    public HttpErrorKind Kind { get; }
    public int StatusCode { get; }
    public string Body { get; }

    private HttpFailure(HttpErrorKind kind, string message, int code = 0, string body = "", Exception? inner = null)
        : base(message, inner)
    {
        Kind = kind;
        StatusCode = code;
        Body = body;
    }

    public static HttpFailure FromStatus(int code, string body) => new(HttpErrorKind.Status, code switch
    {
        401 or 403 => "authentication failed — check the API key",
        429 => "rate limit exceeded",
        _ => $"HTTP {code}: {Http.SummarizeErrorBody(body)}",
    }, code, body);

    public static HttpFailure Timeout() => new(HttpErrorKind.Timeout, "the request timed out");
    public static HttpFailure Network(string text, Exception? inner = null) => new(HttpErrorKind.Network, $"network error: {text}", inner: inner);
    public static HttpFailure Decode(string text) => new(HttpErrorKind.Decode, $"unexpected response: {text}");

    public bool IsTransient => Kind == HttpErrorKind.Network
        || (Kind == HttpErrorKind.Status && (StatusCode == 429 || (StatusCode >= 500 && StatusCode <= 599)));
}

public static class Http
{
    public static HttpClient Client { get; } = CreateClient();

    private static HttpClient CreateClient()
    {
        var client = new HttpClient(new SocketsHttpHandler
        {
            ConnectTimeout = TimeSpan.FromSeconds(15),
            AutomaticDecompression = DecompressionMethods.All,
            PooledConnectionLifetime = TimeSpan.FromMinutes(5),
        })
        {
            Timeout = Timeout.InfiniteTimeSpan,
        };
        client.DefaultRequestHeaders.UserAgent.ParseAdd($"VoiceInk-Windows/{typeof(Http).Assembly.GetName().Version?.ToString(3) ?? "0"}");
        return client;
    }

    /// <summary>Pulls the human-readable message out of a provider's JSON error body.</summary>
    public static string SummarizeErrorBody(string body)
    {
        try
        {
            if (JsonNode.Parse(body) is JsonObject obj)
            {
                JsonNode? msg = obj["error"]?["message"] ?? obj["detail"]?["message"] ?? obj["message"]
                    ?? obj["err_msg"] ?? obj["detail"] ?? obj["error"];
                if (msg is not null)
                {
                    return msg is JsonValue v && v.TryGetValue<string>(out var s) ? s : msg.ToJsonString();
                }
            }
        }
        catch (JsonException)
        {
            // Not JSON: fall through to the plain body.
        }

        var trimmed = body.Trim();
        return trimmed.Length > 300 ? trimmed[..300] + "…" : trimmed;
    }

    /// <summary>Sends the request and returns the parsed JSON body. Maps failures to <see cref="HttpFailure"/>.</summary>
    public static async Task<JsonNode> SendJsonAsync(HttpRequestMessage request, TimeSpan timeout, CancellationToken ct)
    {
        using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeoutCts.CancelAfter(timeout);
        string text;
        try
        {
            using var response = await Client.SendAsync(request, HttpCompletionOption.ResponseContentRead, timeoutCts.Token)
                .ConfigureAwait(false);
            text = await response.Content.ReadAsStringAsync(timeoutCts.Token).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                throw HttpFailure.FromStatus((int)response.StatusCode, text);
            }
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            throw HttpFailure.Timeout();
        }
        catch (HttpRequestException e)
        {
            throw HttpFailure.Network(e.InnerException?.Message ?? e.Message, e);
        }

        try
        {
            return JsonNode.Parse(text) ?? throw HttpFailure.Decode(SummarizeErrorBody(text));
        }
        catch (JsonException e)
        {
            throw HttpFailure.Decode($"{e.Message}: {SummarizeErrorBody(text)}");
        }
    }

    private static readonly JsonSerializerOptions RelaxedJson = new()
    {
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    public static HttpRequestMessage JsonRequest(string url, JsonNode body)
    {
        return new HttpRequestMessage(HttpMethod.Post, url)
        {
            Content = new StringContent(body.ToJsonString(RelaxedJson), System.Text.Encoding.UTF8, "application/json"),
        };
    }

    /// <summary>Percent-encodes everything except RFC 3986 unreserved characters.</summary>
    public static string UrlEncode(string value) => Uri.EscapeDataString(value);
}
