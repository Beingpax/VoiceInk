//! Catalog of transcription and AI providers: names, endpoints, models and
//! the credential each one needs.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TranscriptionProvider {
    Groq,
    #[serde(rename = "openai")]
    OpenAI,
    Deepgram,
    #[serde(rename = "elevenlabs")]
    ElevenLabs,
    Mistral,
    /// Any OpenAI-compatible `/audio/transcriptions` endpoint (e.g. a local
    /// `whisper.cpp` server, `LocalAI`, faster-whisper-server).
    Custom,
    /// Offline whisper.cpp (requires the `local-whisper` build feature).
    Local,
}

impl TranscriptionProvider {
    pub const ALL: [TranscriptionProvider; 7] =
        [Self::OpenAI, Self::Groq, Self::Deepgram, Self::ElevenLabs, Self::Mistral, Self::Custom, Self::Local];

    pub fn display_name(self) -> &'static str {
        match self {
            Self::Groq => "Groq",
            Self::OpenAI => "OpenAI",
            Self::Deepgram => "Deepgram",
            Self::ElevenLabs => "ElevenLabs",
            Self::Mistral => "Mistral",
            Self::Custom => "Custom (OpenAI-compatible)",
            Self::Local => "Local (whisper.cpp)",
        }
    }

    /// Name under which the API key is stored (shared with enhancement
    /// providers), or `None` for providers that never use a key.
    pub fn credential_key(self) -> Option<&'static str> {
        match self {
            Self::Groq => Some("groq"),
            Self::OpenAI => Some("openai"),
            Self::Deepgram => Some("deepgram"),
            Self::ElevenLabs => Some("elevenlabs"),
            Self::Mistral => Some("mistral"),
            Self::Custom => Some("custom-transcription"),
            Self::Local => None,
        }
    }

    pub fn default_model(self) -> &'static str {
        match self {
            Self::Groq => "whisper-large-v3-turbo",
            Self::OpenAI => "gpt-4o-transcribe",
            Self::Deepgram => "nova-3",
            Self::ElevenLabs => "scribe_v2",
            Self::Mistral => "voxtral-mini-latest",
            Self::Custom => "whisper-1",
            Self::Local => "ggml-base.en.bin",
        }
    }

    pub fn models(self) -> &'static [&'static str] {
        match self {
            Self::Groq => &["whisper-large-v3-turbo", "whisper-large-v3"],
            Self::OpenAI => &["gpt-4o-transcribe", "gpt-4o-mini-transcribe", "whisper-1"],
            Self::Deepgram => &["nova-3", "nova-3-medical"],
            Self::ElevenLabs => &["scribe_v2", "scribe_v2_medical"],
            Self::Mistral => &["voxtral-mini-latest"],
            Self::Custom | Self::Local => &[],
        }
    }

    pub fn requires_api_key(self) -> bool {
        !matches!(self, Self::Local | Self::Custom)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum EnhancementProvider {
    #[serde(rename = "openai")]
    OpenAI,
    Anthropic,
    Gemini,
    Groq,
    Cerebras,
    Mistral,
    #[serde(rename = "openrouter")]
    OpenRouter,
    Ollama,
    /// Any OpenAI-compatible `/chat/completions` endpoint (LM Studio, vLLM, ...).
    Custom,
}

impl EnhancementProvider {
    pub const ALL: [EnhancementProvider; 9] = [
        Self::OpenAI,
        Self::Anthropic,
        Self::Gemini,
        Self::Groq,
        Self::Cerebras,
        Self::Mistral,
        Self::OpenRouter,
        Self::Ollama,
        Self::Custom,
    ];

    pub fn display_name(self) -> &'static str {
        match self {
            Self::OpenAI => "OpenAI",
            Self::Anthropic => "Anthropic",
            Self::Gemini => "Gemini",
            Self::Groq => "Groq",
            Self::Cerebras => "Cerebras",
            Self::Mistral => "Mistral",
            Self::OpenRouter => "OpenRouter",
            Self::Ollama => "Ollama",
            Self::Custom => "Custom (OpenAI-compatible)",
        }
    }

    /// Name under which the API key is stored, or `None` for keyless providers.
    pub fn credential_key(self) -> Option<&'static str> {
        match self {
            Self::OpenAI => Some("openai"),
            Self::Anthropic => Some("anthropic"),
            Self::Gemini => Some("gemini"),
            Self::Groq => Some("groq"),
            Self::Cerebras => Some("cerebras"),
            Self::Mistral => Some("mistral"),
            Self::OpenRouter => Some("openrouter"),
            Self::Ollama => None,
            Self::Custom => Some("custom-enhancement"),
        }
    }

    /// Chat endpoint; `None` for providers whose URL comes from the config.
    pub fn endpoint(self) -> Option<&'static str> {
        match self {
            Self::OpenAI => Some("https://api.openai.com/v1/chat/completions"),
            Self::Anthropic => Some("https://api.anthropic.com/v1/messages"),
            Self::Gemini => Some("https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"),
            Self::Groq => Some("https://api.groq.com/openai/v1/chat/completions"),
            Self::Cerebras => Some("https://api.cerebras.ai/v1/chat/completions"),
            Self::Mistral => Some("https://api.mistral.ai/v1/chat/completions"),
            Self::OpenRouter => Some("https://openrouter.ai/api/v1/chat/completions"),
            Self::Ollama | Self::Custom => None,
        }
    }

    /// Defaults match `AIProvider.defaultModel` in the macOS app.
    pub fn default_model(self) -> &'static str {
        match self {
            Self::Cerebras => "qwen-3.8-27b",
            Self::Groq | Self::OpenRouter => "qwen/qwen3.8-27b",
            Self::Gemini => "gemini-3.8-flash",
            Self::Anthropic => "claude-sonnet-5",
            Self::OpenAI => "gpt-6-luna",
            Self::Mistral => "mistral-small-latest",
            Self::Ollama => "mistral",
            Self::Custom => "",
        }
    }

    pub fn models(self) -> &'static [&'static str] {
        match self {
            Self::Cerebras => &["qwen-3.8-27b", "gpt-oss-120b"],
            Self::Groq => &["qwen/qwen3.8-27b", "openai/gpt-oss-120b", "openai/gpt-oss-20b"],
            Self::Gemini => &[
                "gemini-3.8-flash",
                "gemini-3.7-flash",
                "gemini-3.5-flash",
                "gemini-3.5-flash-lite",
                "gemini-3.1-pro-preview",
            ],
            Self::Anthropic => &["claude-sonnet-5", "claude-haiku-4-5"],
            Self::OpenAI => &["gpt-6-luna", "gpt-6-sol", "gpt-5.6-luna", "gpt-5.5", "gpt-5.4-mini", "gpt-4.1-mini"],
            Self::Mistral => &["mistral-small-latest", "mistral-medium-latest", "mistral-large-latest"],
            Self::OpenRouter | Self::Ollama | Self::Custom => &[],
        }
    }

    pub fn requires_api_key(self) -> bool {
        !matches!(self, Self::Ollama | Self::Custom)
    }

    /// `OpenRouter` and local servers are not rate limited client-side (as on macOS).
    pub fn is_rate_limited(self) -> bool {
        !matches!(self, Self::OpenRouter | Self::Ollama)
    }
}

/// Languages offered in the menu and dashboard (`auto` = provider auto-detect).
pub const LANGUAGES: &[(&str, &str)] = &[
    ("auto", "Auto-detect"),
    ("en", "English"),
    ("de", "German"),
    ("fr", "French"),
    ("es", "Spanish"),
    ("it", "Italian"),
    ("pt", "Portuguese"),
    ("nl", "Dutch"),
    ("pl", "Polish"),
    ("ru", "Russian"),
    ("uk", "Ukrainian"),
    ("tr", "Turkish"),
    ("ja", "Japanese"),
    ("zh", "Chinese"),
    ("ko", "Korean"),
    ("hi", "Hindi"),
    ("ar", "Arabic"),
];

/// Every credential name the app knows about, sorted and de-duplicated
/// (an `OpenAI` key serves both transcription and enhancement).
pub fn credential_keys() -> Vec<&'static str> {
    let mut names: Vec<&str> = TranscriptionProvider::ALL
        .iter()
        .filter_map(|p| p.credential_key())
        .chain(EnhancementProvider::ALL.iter().filter_map(|p| p.credential_key()))
        .collect();
    names.sort_unstable();
    names.dedup();
    names
}
