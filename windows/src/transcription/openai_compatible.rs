//! `POST /audio/transcriptions` as used by `OpenAI`, Groq, Mistral and local
//! servers (port of `OpenAITranscriptionClient` /
//! `OpenAICompatibleTranscriptionService`).

use super::{Transcriber, TranscriptionError, TranscriptionRequest, non_empty};
use crate::http::{self, Multipart};
use std::time::Duration;

/// `OpenAI` caps the Whisper prompt at ~224 tokens; stay well below.
const MAX_PROMPT_CHARS: usize = 600;

pub struct OpenAiCompatible {
    provider: &'static str,
    endpoint: String,
    api_key: Option<String>,
    model: String,
    timeout: Duration,
}

impl OpenAiCompatible {
    pub fn new(
        provider: &'static str,
        endpoint: &str,
        api_key: Option<String>,
        model: String,
        timeout: Duration,
    ) -> Self {
        Self { provider, endpoint: endpoint.to_string(), api_key, model, timeout }
    }
}

/// Whisper-style prompt from custom vocabulary, bounded in length.
fn vocabulary_prompt(vocabulary: &[String]) -> Option<String> {
    let mut prompt = String::new();
    for word in vocabulary.iter().map(|w| w.trim()).filter(|w| !w.is_empty()) {
        if prompt.len() + word.len() + 2 > MAX_PROMPT_CHARS {
            break;
        }
        if !prompt.is_empty() {
            prompt.push_str(", ");
        }
        prompt.push_str(word);
    }
    (!prompt.is_empty()).then_some(prompt)
}

impl Transcriber for OpenAiCompatible {
    fn describe(&self) -> String {
        format!("{} {}", self.provider, self.model)
    }

    fn transcribe(&self, request: &TranscriptionRequest<'_>) -> Result<String, TranscriptionError> {
        let mut form = Multipart::new()
            .file("file", "audio.wav", "audio/wav", request.wav)
            .text("model", &self.model)
            .text("response_format", "json")
            .text("temperature", "0");
        if let Some(lang) = request.language {
            form = form.text("language", lang);
        }
        if let Some(prompt) = vocabulary_prompt(request.vocabulary) {
            form = form.text("prompt", &prompt);
        }
        let (content_type, body) = form.finish();

        let mut req = http::agent(self.timeout).post(&self.endpoint).set("Content-Type", &content_type);
        if let Some(key) = self.api_key.as_deref().filter(|k| !k.is_empty()) {
            req = req.set("Authorization", &format!("Bearer {key}"));
        }
        let json = http::send_bytes(req, &body)?;
        let text = json.get("text").and_then(|t| t.as_str()).ok_or(TranscriptionError::NoTranscript)?;
        non_empty(text)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::http::test_server::{Route, serve};

    #[test]
    fn vocabulary_prompt_is_bounded() {
        assert_eq!(vocabulary_prompt(&[]), None);
        let words: Vec<String> = (0..500).map(|i| format!("word{i}")).collect();
        let p = vocabulary_prompt(&words).unwrap();
        assert!(p.len() <= MAX_PROMPT_CHARS);
        assert!(p.starts_with("word0, word1"));
    }

    #[test]
    fn sends_multipart_and_reads_text() {
        let (base, server) =
            serve(vec![Route { path: "/v1/audio/transcriptions", status: 200, body: r#"{"text":" hello "}"# }]);
        let client = OpenAiCompatible::new(
            "Custom",
            &format!("{base}/v1/audio/transcriptions"),
            Some("sk".into()),
            "whisper-1".into(),
            Duration::from_secs(5),
        );
        let vocabulary = vec!["VoiceInk".to_string()];
        let request =
            TranscriptionRequest { wav: b"RIFF", samples: &[], language: Some("de"), vocabulary: &vocabulary };
        assert_eq!(client.transcribe(&request).unwrap(), "hello");
        let seen = server.join().unwrap();
        assert!(seen[0].contains("name=\"model\"\r\n\r\nwhisper-1"));
        assert!(seen[0].contains("name=\"language\"\r\n\r\nde"));
        assert!(seen[0].contains("name=\"prompt\"\r\n\r\nVoiceInk"));
    }
}
