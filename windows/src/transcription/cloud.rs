//! Cloud transcription clients.

use super::{url_encode, TranscriptionError, TranscriptionRequest};
use crate::http::{self, Multipart};
use std::time::Duration;

/// Whisper-style prompt from custom vocabulary (OpenAI-compatible APIs cap it at ~224 tokens).
fn vocabulary_prompt(vocabulary: &[String]) -> Option<String> {
    let words: Vec<&str> = vocabulary
        .iter()
        .map(|w| w.trim())
        .filter(|w| !w.is_empty())
        .collect();
    if words.is_empty() {
        return None;
    }
    let mut prompt = String::new();
    for w in words {
        if prompt.len() + w.len() + 2 > 600 {
            break;
        }
        if !prompt.is_empty() {
            prompt.push_str(", ");
        }
        prompt.push_str(w);
    }
    Some(prompt)
}

fn text_field(json: &serde_json::Value) -> Result<String, TranscriptionError> {
    json.get("text")
        .and_then(|t| t.as_str())
        .map(str::to_string)
        .ok_or(TranscriptionError::NoTranscript)
}

/// `POST /audio/transcriptions` as used by OpenAI, Groq, Mistral and local servers
/// (port of `OpenAITranscriptionClient` / `OpenAICompatibleTranscriptionService`).
pub fn openai_compatible(
    endpoint: &str,
    api_key: Option<&str>,
    model: &str,
    request: &TranscriptionRequest<'_>,
    timeout: Duration,
) -> Result<String, TranscriptionError> {
    let mut form = Multipart::new()
        .file("file", "audio.wav", "audio/wav", request.wav)
        .text("model", model)
        .text("response_format", "json")
        .text("temperature", "0");
    if let Some(lang) = request.language {
        form = form.text("language", lang);
    }
    if let Some(prompt) = vocabulary_prompt(request.vocabulary) {
        form = form.text("prompt", &prompt);
    }
    let (content_type, body) = form.finish();

    let mut req = http::agent(timeout)
        .post(endpoint)
        .set("Content-Type", &content_type);
    if let Some(key) = api_key.filter(|k| !k.is_empty()) {
        req = req.set("Authorization", &format!("Bearer {key}"));
    }
    text_field(&http::send_bytes(req, &body)?)
}

/// Deepgram pre-recorded API. `nova-3` without a language uses `language=multi`,
/// like `DeepgramProvider.transcribe`.
pub fn deepgram(
    api_key: &str,
    model: &str,
    request: &TranscriptionRequest<'_>,
    timeout: Duration,
) -> Result<String, TranscriptionError> {
    let language = match request.language {
        Some(l) => l.to_string(),
        None if model == "nova-3" => "multi".to_string(),
        None => "en".to_string(),
    };
    let mut url = format!(
        "https://api.deepgram.com/v1/listen?model={}&smart_format=true&punctuate=true&language={}",
        url_encode(model),
        url_encode(&language)
    );
    for term in request
        .vocabulary
        .iter()
        .map(|t| t.trim())
        .filter(|t| !t.is_empty())
        .take(100)
    {
        url.push_str("&keyterm=");
        url.push_str(&url_encode(term));
    }

    let req = http::agent(timeout)
        .post(&url)
        .set("Authorization", &format!("Token {api_key}"))
        .set("Content-Type", "audio/wav");
    let json = http::send_bytes(req, request.wav)?;
    json.pointer("/results/channels/0/alternatives/0/transcript")
        .and_then(|t| t.as_str())
        .map(str::to_string)
        .ok_or(TranscriptionError::NoTranscript)
}

/// ElevenLabs Scribe speech-to-text.
pub fn elevenlabs(
    api_key: &str,
    model: &str,
    request: &TranscriptionRequest<'_>,
    timeout: Duration,
) -> Result<String, TranscriptionError> {
    let mut form = Multipart::new()
        .file("file", "audio.wav", "audio/wav", request.wav)
        .text("model_id", model)
        .text("tag_audio_events", "false");
    if let Some(lang) = request.language {
        form = form.text("language_code", lang);
    }
    let (content_type, body) = form.finish();
    let req = http::agent(timeout)
        .post("https://api.elevenlabs.io/v1/speech-to-text")
        .set("xi-api-key", api_key)
        .set("Content-Type", &content_type);
    text_field(&http::send_bytes(req, &body)?)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn vocabulary_prompt_is_bounded() {
        assert_eq!(vocabulary_prompt(&[]), None);
        let words: Vec<String> = (0..500).map(|i| format!("word{i}")).collect();
        let p = vocabulary_prompt(&words).unwrap();
        assert!(p.len() <= 600);
        assert!(p.starts_with("word0, word1"));
    }
}
