//! Speech-to-text providers.
//!
//! Each provider receives a 16 kHz mono 16-bit WAV, the same format the macOS
//! `CoreAudioRecorder` writes, so request shapes match the Swift clients.

mod cloud;
#[cfg(feature = "local-whisper")]
pub mod local;

use crate::config::{TranscriptionProvider, TranscriptionSettings};
use crate::credentials;
use crate::http::HttpError;
use std::time::Duration;

#[derive(Debug)]
pub enum TranscriptionError {
    MissingApiKey(&'static str),
    Http(HttpError),
    NoTranscript,
    NotConfigured(String),
    Local(String),
}

impl std::fmt::Display for TranscriptionError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::MissingApiKey(p) => write!(f, "no API key configured for {p}"),
            Self::Http(e) => write!(f, "{e}"),
            Self::NoTranscript => write!(f, "the provider returned no transcript"),
            Self::NotConfigured(m) => write!(f, "{m}"),
            Self::Local(m) => write!(f, "local transcription failed: {m}"),
        }
    }
}

impl std::error::Error for TranscriptionError {}

impl From<HttpError> for TranscriptionError {
    fn from(e: HttpError) -> Self {
        Self::Http(e)
    }
}

pub struct TranscriptionRequest<'a> {
    /// 16 kHz mono PCM16 WAV file contents.
    pub wav: &'a [u8],
    /// The same audio as `f32` samples (used by the local engine).
    pub samples: &'a [f32],
    pub language: Option<&'a str>,
    pub vocabulary: &'a [String],
}

/// Transcribes with the configured provider.
pub fn transcribe(
    settings: &TranscriptionSettings,
    request: &TranscriptionRequest<'_>,
) -> Result<String, TranscriptionError> {
    let provider = settings.provider;
    let model = settings.model_name();
    let timeout = Duration::from_secs(settings.timeout_secs.max(10));

    let api_key = || -> Result<String, TranscriptionError> {
        credentials::get(provider.key_name())
            .ok_or(TranscriptionError::MissingApiKey(provider.display_name()))
    };

    let text = match provider {
        TranscriptionProvider::Groq => cloud::openai_compatible(
            "https://api.groq.com/openai/v1/audio/transcriptions",
            Some(&api_key()?),
            &model,
            request,
            timeout,
        )?,
        TranscriptionProvider::OpenAI => cloud::openai_compatible(
            "https://api.openai.com/v1/audio/transcriptions",
            Some(&api_key()?),
            &model,
            request,
            timeout,
        )?,
        TranscriptionProvider::Mistral => cloud::openai_compatible(
            "https://api.mistral.ai/v1/audio/transcriptions",
            Some(&api_key()?),
            &model,
            request,
            timeout,
        )?,
        TranscriptionProvider::Custom => {
            if settings.custom_endpoint.trim().is_empty() {
                return Err(TranscriptionError::NotConfigured(
                    "set transcription.custom_endpoint in the settings file".into(),
                ));
            }
            let key = credentials::get(provider.key_name());
            cloud::openai_compatible(
                settings.custom_endpoint.trim(),
                key.as_deref(),
                &model,
                request,
                timeout,
            )?
        }
        TranscriptionProvider::Deepgram => cloud::deepgram(&api_key()?, &model, request, timeout)?,
        TranscriptionProvider::ElevenLabs => {
            cloud::elevenlabs(&api_key()?, &model, request, timeout)?
        }
        TranscriptionProvider::Local => local_transcribe(settings, &model, request)?,
    };

    let text = text.trim().to_string();
    if text.is_empty() {
        return Err(TranscriptionError::NoTranscript);
    }
    Ok(text)
}

#[cfg(feature = "local-whisper")]
fn local_transcribe(
    settings: &TranscriptionSettings,
    model: &str,
    request: &TranscriptionRequest<'_>,
) -> Result<String, TranscriptionError> {
    let dir = settings
        .local_models_dir
        .clone()
        .unwrap_or_else(|| crate::config::data_dir().join("models"));
    local::transcribe(
        &dir.join(model),
        request.samples,
        request.language,
        request.vocabulary,
    )
    .map_err(TranscriptionError::Local)
}

#[cfg(not(feature = "local-whisper"))]
fn local_transcribe(
    _settings: &TranscriptionSettings,
    _model: &str,
    _request: &TranscriptionRequest<'_>,
) -> Result<String, TranscriptionError> {
    Err(TranscriptionError::NotConfigured(
        "this build has no local engine; rebuild with `--features local-whisper` or use the custom provider with a local whisper.cpp server".into(),
    ))
}

/// Minimal percent-encoding for query parameters.
pub(crate) fn url_encode(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for b in value.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(b as char)
            }
            _ => out.push_str(&format!("%{b:02X}")),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    #[test]
    fn url_encodes() {
        assert_eq!(super::url_encode("a b&c/ü"), "a%20b%26c%2F%C3%BC");
    }
}
