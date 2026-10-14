using System.Text.Json.Serialization;

namespace VoiceInk.Core.Config;

public enum TranscriptionProvider
{
    [JsonStringEnumMemberName("groq")] Groq,
    [JsonStringEnumMemberName("openai")] OpenAI,
    [JsonStringEnumMemberName("deepgram")] Deepgram,
    [JsonStringEnumMemberName("elevenlabs")] ElevenLabs,
    [JsonStringEnumMemberName("mistral")] Mistral,

    /// <summary>Any OpenAI-compatible <c>/audio/transcriptions</c> endpoint (LocalAI, faster-whisper-server, ...).</summary>
    [JsonStringEnumMemberName("custom")] Custom,

    /// <summary>Offline whisper.cpp through Whisper.net.</summary>
    [JsonStringEnumMemberName("local")] Local,
}

public static class TranscriptionProviders
{
    public static readonly IReadOnlyList<TranscriptionProvider> All =
    [
        TranscriptionProvider.OpenAI,
        TranscriptionProvider.Groq,
        TranscriptionProvider.Deepgram,
        TranscriptionProvider.ElevenLabs,
        TranscriptionProvider.Mistral,
        TranscriptionProvider.Custom,
        TranscriptionProvider.Local,
    ];

    public static string DisplayName(this TranscriptionProvider p) => p switch
    {
        TranscriptionProvider.Groq => "Groq",
        TranscriptionProvider.OpenAI => "OpenAI",
        TranscriptionProvider.Deepgram => "Deepgram",
        TranscriptionProvider.ElevenLabs => "ElevenLabs",
        TranscriptionProvider.Mistral => "Mistral",
        TranscriptionProvider.Custom => "Custom (OpenAI-compatible)",
        TranscriptionProvider.Local => "Local (Whisper.net)",
        _ => p.ToString(),
    };

    /// <summary>Name under which the API key is stored (shared with enhancement providers).</summary>
    public static string KeyName(this TranscriptionProvider p) => p switch
    {
        TranscriptionProvider.Groq => "groq",
        TranscriptionProvider.OpenAI => "openai",
        TranscriptionProvider.Deepgram => "deepgram",
        TranscriptionProvider.ElevenLabs => "elevenlabs",
        TranscriptionProvider.Mistral => "mistral",
        TranscriptionProvider.Custom => "custom-transcription",
        _ => "",
    };

    public static string DefaultModel(this TranscriptionProvider p) => p switch
    {
        TranscriptionProvider.Groq => "whisper-large-v3-turbo",
        TranscriptionProvider.OpenAI => "gpt-4o-transcribe",
        TranscriptionProvider.Deepgram => "nova-3",
        TranscriptionProvider.ElevenLabs => "scribe_v2",
        TranscriptionProvider.Mistral => "voxtral-mini-latest",
        TranscriptionProvider.Custom => "whisper-1",
        TranscriptionProvider.Local => "ggml-base.bin",
        _ => "",
    };

    public static IReadOnlyList<string> Models(this TranscriptionProvider p) => p switch
    {
        TranscriptionProvider.Groq => ["whisper-large-v3-turbo", "whisper-large-v3"],
        TranscriptionProvider.OpenAI => ["gpt-4o-transcribe", "gpt-4o-mini-transcribe", "whisper-1"],
        TranscriptionProvider.Deepgram => ["nova-3", "nova-3-medical"],
        TranscriptionProvider.ElevenLabs => ["scribe_v2", "scribe_v2_medical"],
        TranscriptionProvider.Mistral => ["voxtral-mini-latest"],
        _ => [],
    };

    public static bool RequiresApiKey(this TranscriptionProvider p) =>
        p is not (TranscriptionProvider.Local or TranscriptionProvider.Custom);
}

public enum EnhancementProvider
{
    [JsonStringEnumMemberName("openai")] OpenAI,
    [JsonStringEnumMemberName("anthropic")] Anthropic,
    [JsonStringEnumMemberName("gemini")] Gemini,
    [JsonStringEnumMemberName("groq")] Groq,
    [JsonStringEnumMemberName("cerebras")] Cerebras,
    [JsonStringEnumMemberName("mistral")] Mistral,
    [JsonStringEnumMemberName("openrouter")] OpenRouter,
    [JsonStringEnumMemberName("ollama")] Ollama,

    /// <summary>Any OpenAI-compatible <c>/chat/completions</c> endpoint (LM Studio, vLLM, ...).</summary>
    [JsonStringEnumMemberName("custom")] Custom,
}

public static class EnhancementProviders
{
    public static readonly IReadOnlyList<EnhancementProvider> All =
    [
        EnhancementProvider.OpenAI,
        EnhancementProvider.Anthropic,
        EnhancementProvider.Gemini,
        EnhancementProvider.Groq,
        EnhancementProvider.Cerebras,
        EnhancementProvider.Mistral,
        EnhancementProvider.OpenRouter,
        EnhancementProvider.Ollama,
        EnhancementProvider.Custom,
    ];

    public static string DisplayName(this EnhancementProvider p) => p switch
    {
        EnhancementProvider.OpenAI => "OpenAI",
        EnhancementProvider.Anthropic => "Anthropic",
        EnhancementProvider.Gemini => "Gemini",
        EnhancementProvider.Groq => "Groq",
        EnhancementProvider.Cerebras => "Cerebras",
        EnhancementProvider.Mistral => "Mistral",
        EnhancementProvider.OpenRouter => "OpenRouter",
        EnhancementProvider.Ollama => "Ollama",
        EnhancementProvider.Custom => "Custom (OpenAI-compatible)",
        _ => p.ToString(),
    };

    public static string KeyName(this EnhancementProvider p) => p switch
    {
        EnhancementProvider.OpenAI => "openai",
        EnhancementProvider.Anthropic => "anthropic",
        EnhancementProvider.Gemini => "gemini",
        EnhancementProvider.Groq => "groq",
        EnhancementProvider.Cerebras => "cerebras",
        EnhancementProvider.Mistral => "mistral",
        EnhancementProvider.OpenRouter => "openrouter",
        EnhancementProvider.Custom => "custom-enhancement",
        _ => "",
    };

    /// <summary>Chat endpoint; <c>null</c> for providers whose URL comes from the config.</summary>
    public static string? Endpoint(this EnhancementProvider p) => p switch
    {
        EnhancementProvider.OpenAI => "https://api.openai.com/v1/chat/completions",
        EnhancementProvider.Anthropic => "https://api.anthropic.com/v1/messages",
        EnhancementProvider.Gemini => "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
        EnhancementProvider.Groq => "https://api.groq.com/openai/v1/chat/completions",
        EnhancementProvider.Cerebras => "https://api.cerebras.ai/v1/chat/completions",
        EnhancementProvider.Mistral => "https://api.mistral.ai/v1/chat/completions",
        EnhancementProvider.OpenRouter => "https://openrouter.ai/api/v1/chat/completions",
        _ => null,
    };

    /// <summary>Defaults match <c>AIProvider.defaultModel</c> in the macOS app.</summary>
    public static string DefaultModel(this EnhancementProvider p) => p switch
    {
        EnhancementProvider.Cerebras => "qwen-3.8-27b",
        EnhancementProvider.Groq => "qwen/qwen3.8-27b",
        EnhancementProvider.Gemini => "gemini-3.8-flash",
        EnhancementProvider.Anthropic => "claude-sonnet-5",
        EnhancementProvider.OpenAI => "gpt-6-luna",
        EnhancementProvider.Mistral => "mistral-small-latest",
        EnhancementProvider.OpenRouter => "qwen/qwen3.8-27b",
        EnhancementProvider.Ollama => "mistral",
        _ => "",
    };

    public static IReadOnlyList<string> Models(this EnhancementProvider p) => p switch
    {
        EnhancementProvider.Cerebras => ["qwen-3.8-27b", "gpt-oss-120b"],
        EnhancementProvider.Groq => ["qwen/qwen3.8-27b", "openai/gpt-oss-120b", "openai/gpt-oss-20b"],
        EnhancementProvider.Gemini =>
        [
            "gemini-3.8-flash", "gemini-3.7-flash", "gemini-3.5-flash", "gemini-3.5-flash-lite", "gemini-3.1-pro-preview",
        ],
        EnhancementProvider.Anthropic => ["claude-sonnet-5", "claude-haiku-4-5"],
        EnhancementProvider.OpenAI =>
        [
            "gpt-6-luna", "gpt-6-sol", "gpt-5.6-luna", "gpt-5.5", "gpt-5.4-mini", "gpt-4.1-mini",
        ],
        EnhancementProvider.Mistral => ["mistral-small-latest", "mistral-medium-latest", "mistral-large-latest"],
        _ => [],
    };

    public static bool RequiresApiKey(this EnhancementProvider p) =>
        p is not (EnhancementProvider.Ollama or EnhancementProvider.Custom);

    /// <summary>OpenRouter and local servers are not rate limited client-side (as on macOS).</summary>
    public static bool IsRateLimited(this EnhancementProvider p) =>
        p is not (EnhancementProvider.OpenRouter or EnhancementProvider.Ollama);
}

public static class Languages
{
    /// <summary>Languages offered in the UI (<c>auto</c> = provider auto-detect).</summary>
    public static readonly IReadOnlyList<(string Code, string Name)> All =
    [
        ("auto", "Auto-detect"), ("en", "English"), ("de", "German"), ("fr", "French"), ("es", "Spanish"),
        ("it", "Italian"), ("pt", "Portuguese"), ("nl", "Dutch"), ("pl", "Polish"), ("ru", "Russian"),
        ("uk", "Ukrainian"), ("tr", "Turkish"), ("ja", "Japanese"), ("zh", "Chinese"), ("ko", "Korean"),
        ("hi", "Hindi"), ("ar", "Arabic"),
    ];
}
