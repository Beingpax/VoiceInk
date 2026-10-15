//! `ElevenLabs` Scribe speech-to-text (`ElevenLabsProvider`).

use super::{Transcriber, TranscriptionError, TranscriptionRequest, non_empty};
use crate::http::{self, Multipart};
use std::time::Duration;

const ENDPOINT: &str = "https://api.elevenlabs.io/v1/speech-to-text";

pub struct ElevenLabs {
    api_key: String,
    model: String,
    timeout: Duration,
}

impl ElevenLabs {
    pub fn new(api_key: String, model: String, timeout: Duration) -> Self {
        Self { api_key, model, timeout }
    }
}

impl Transcriber for ElevenLabs {
    fn describe(&self) -> String {
        format!("ElevenLabs {}", self.model)
    }

    fn transcribe(&self, request: &TranscriptionRequest<'_>) -> Result<String, TranscriptionError> {
        let mut form = Multipart::new()
            .file("file", "audio.wav", "audio/wav", request.wav)
            .text("model_id", &self.model)
            .text("tag_audio_events", "false");
        if let Some(lang) = request.language {
            form = form.text("language_code", lang);
        }
        let (content_type, body) = form.finish();
        let req = http::agent(self.timeout)
            .post(ENDPOINT)
            .set("xi-api-key", &self.api_key)
            .set("Content-Type", &content_type);
        let json = http::send_bytes(req, &body)?;
        let text = json.get("text").and_then(|t| t.as_str()).ok_or(TranscriptionError::NoTranscript)?;
        non_empty(text)
    }
}
