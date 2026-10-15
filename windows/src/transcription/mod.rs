//! Speech-to-text providers behind the [`Transcriber`] trait.
//!
//! Each provider receives a 16 kHz mono 16-bit WAV, the same format the macOS
//! `CoreAudioRecorder` writes, so request shapes match the Swift clients.
//! [`create`] picks the implementation for the configured provider; the
//! pipeline only ever sees the trait.

mod deepgram;
mod elevenlabs;
#[cfg(feature = "local-whisper")]
mod local;
mod openai_compatible;

pub use deepgram::Deepgram;
pub use elevenlabs::ElevenLabs;
pub use openai_compatible::OpenAiCompatible;

use crate::config::{TranscriptionProvider, TranscriptionSettings};
use crate::credentials::SecretStore;
use crate::http::HttpError;
use std::path::Path;
use std::time::Duration;

const MIN_TIMEOUT: Duration = Duration::from_secs(10);

#[derive(Debug, thiserror::Error)]
pub enum TranscriptionError {
    #[error("no API key configured for {0}")]
    MissingApiKey(&'static str),
    #[error(transparent)]
    Http(#[from] HttpError),
    #[error("the provider returned no transcript")]
    NoTranscript,
    #[error("{0}")]
    NotConfigured(String),
    #[error("local transcription failed: {0}")]
    Local(String),
}

/// One recording to transcribe.
#[derive(Debug, Clone, Copy)]
pub struct TranscriptionRequest<'a> {
    /// 16 kHz mono PCM16 WAV file contents.
    pub wav: &'a [u8],
    /// The same audio as `f32` samples (used by the local engine).
    pub samples: &'a [f32],
    /// ISO-639-1 code, `None` for auto-detection.
    pub language: Option<&'a str>,
    /// Names and terms the provider should spell correctly.
    pub vocabulary: &'a [String],
}

/// A speech-to-text engine.
pub trait Transcriber: Send + Sync {
    /// Human-readable engine name for history, e.g. `"OpenAI gpt-4o-transcribe"`.
    fn describe(&self) -> String;

    /// # Errors
    /// Returns [`TranscriptionError`] when the provider fails or returns nothing.
    fn transcribe(&self, request: &TranscriptionRequest<'_>) -> Result<String, TranscriptionError>;
}

/// Builds the transcriber for the configured provider.
///
/// # Errors
/// Returns [`TranscriptionError::MissingApiKey`] or
/// [`TranscriptionError::NotConfigured`] when the provider can't be used yet.
pub fn create(
    settings: &TranscriptionSettings,
    secrets: &dyn SecretStore,
    models_dir: &Path,
) -> Result<Box<dyn Transcriber>, TranscriptionError> {
    let provider = settings.provider;
    let model = settings.model_name();
    let timeout = Duration::from_secs(settings.timeout_secs).max(MIN_TIMEOUT);
    let key = || provider.credential_key().and_then(|k| secrets.get(k));
    let required_key = || key().ok_or(TranscriptionError::MissingApiKey(provider.display_name()));
    let openai_like = |endpoint: &str, api_key| -> Box<dyn Transcriber> {
        Box::new(OpenAiCompatible::new(provider.display_name(), endpoint, api_key, model.clone(), timeout))
    };

    Ok(match provider {
        TranscriptionProvider::OpenAI => {
            openai_like("https://api.openai.com/v1/audio/transcriptions", Some(required_key()?))
        }
        TranscriptionProvider::Groq => {
            openai_like("https://api.groq.com/openai/v1/audio/transcriptions", Some(required_key()?))
        }
        TranscriptionProvider::Mistral => {
            openai_like("https://api.mistral.ai/v1/audio/transcriptions", Some(required_key()?))
        }
        TranscriptionProvider::Custom => {
            let endpoint = settings.custom_endpoint.trim();
            if endpoint.is_empty() {
                return Err(TranscriptionError::NotConfigured(
                    "set the custom transcription endpoint in Settings".into(),
                ));
            }
            openai_like(endpoint, key())
        }
        TranscriptionProvider::Deepgram => Box::new(Deepgram::new(required_key()?, model, timeout)),
        TranscriptionProvider::ElevenLabs => Box::new(ElevenLabs::new(required_key()?, model, timeout)),
        TranscriptionProvider::Local => local_engine(settings, models_dir, &model)?,
    })
}

#[cfg(feature = "local-whisper")]
fn local_engine(
    settings: &TranscriptionSettings,
    models_dir: &Path,
    model: &str,
) -> Result<Box<dyn Transcriber>, TranscriptionError> {
    let dir = settings.local_models_dir.as_deref().unwrap_or(models_dir);
    Ok(Box::new(local::LocalWhisper::new(dir.join(model))))
}

#[cfg(not(feature = "local-whisper"))]
fn local_engine(
    _settings: &TranscriptionSettings,
    _models_dir: &Path,
    _model: &str,
) -> Result<Box<dyn Transcriber>, TranscriptionError> {
    Err(TranscriptionError::NotConfigured(
        "this build has no local engine; rebuild with `--features local-whisper` or use the custom provider with a local whisper.cpp server".into(),
    ))
}

/// Trims the transcript and rejects empty results.
fn non_empty(text: &str) -> Result<String, TranscriptionError> {
    let text = text.trim();
    if text.is_empty() { Err(TranscriptionError::NoTranscript) } else { Ok(text.to_string()) }
}

/// Minimal percent-encoding for query parameters.
fn url_encode(value: &str) -> String {
    use std::fmt::Write;
    let mut out = String::with_capacity(value.len());
    for b in value.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => out.push(char::from(b)),
            _ => {
                let _ = write!(out, "%{b:02X}");
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::credentials::MemoryStore;

    #[test]
    fn url_encodes() {
        assert_eq!(url_encode("a b&c/ü"), "a%20b%26c%2F%C3%BC");
    }

    #[test]
    fn factory_requires_keys_and_endpoints() {
        let none = MemoryStore::default();
        let mut settings = TranscriptionSettings::default();
        let dir = Path::new("models");
        assert!(matches!(create(&settings, &none, dir), Err(TranscriptionError::MissingApiKey("OpenAI"))));

        let keys = MemoryStore::with(&[("openai", "sk")]);
        assert_eq!(create(&settings, &keys, dir).unwrap().describe(), "OpenAI gpt-4o-transcribe");

        settings.provider = TranscriptionProvider::Custom;
        settings.custom_endpoint = " ".into();
        assert!(matches!(create(&settings, &none, dir), Err(TranscriptionError::NotConfigured(_))));
        settings.custom_endpoint = "http://localhost/v1/audio/transcriptions".into();
        assert!(create(&settings, &none, dir).is_ok(), "custom endpoints may be keyless");
    }
}
