//! Deepgram pre-recorded transcription (`DeepgramProvider`).

use super::{Transcriber, TranscriptionError, TranscriptionRequest, non_empty, url_encode};
use crate::http;
use std::fmt::Write;
use std::time::Duration;

/// Deepgram accepts at most 100 keyterms per request.
const MAX_KEYTERMS: usize = 100;

pub struct Deepgram {
    api_key: String,
    model: String,
    timeout: Duration,
}

impl Deepgram {
    pub fn new(api_key: String, model: String, timeout: Duration) -> Self {
        Self { api_key, model, timeout }
    }

    /// `nova-3` without a language uses multilingual mode, like the macOS app.
    fn language(&self, requested: Option<&str>) -> String {
        match requested {
            Some(lang) => lang.to_string(),
            None if self.model == "nova-3" => "multi".to_string(),
            None => "en".to_string(),
        }
    }

    fn url(&self, request: &TranscriptionRequest<'_>) -> String {
        let mut url = format!(
            "https://api.deepgram.com/v1/listen?model={}&smart_format=true&punctuate=true&language={}",
            url_encode(&self.model),
            url_encode(&self.language(request.language))
        );
        for term in request.vocabulary.iter().map(|t| t.trim()).filter(|t| !t.is_empty()).take(MAX_KEYTERMS) {
            let _ = write!(url, "&keyterm={}", url_encode(term));
        }
        url
    }
}

impl Transcriber for Deepgram {
    fn describe(&self) -> String {
        format!("Deepgram {}", self.model)
    }

    fn transcribe(&self, request: &TranscriptionRequest<'_>) -> Result<String, TranscriptionError> {
        let req = http::agent(self.timeout)
            .post(&self.url(request))
            .set("Authorization", &format!("Token {}", self.api_key))
            .set("Content-Type", "audio/wav");
        let json = http::send_bytes(req, request.wav)?;
        let text = json
            .pointer("/results/channels/0/alternatives/0/transcript")
            .and_then(|t| t.as_str())
            .ok_or(TranscriptionError::NoTranscript)?;
        non_empty(text)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builds_query_with_language_and_keyterms() {
        let dg = Deepgram::new("k".into(), "nova-3".into(), Duration::from_secs(5));
        let vocabulary = vec!["Voice Ink".to_string(), " ".to_string()];
        let request = TranscriptionRequest { wav: &[], samples: &[], language: None, vocabulary: &vocabulary };
        let url = dg.url(&request);
        assert!(url.contains("model=nova-3"));
        assert!(url.contains("language=multi"));
        assert!(url.ends_with("&keyterm=Voice%20Ink"));
        assert_eq!(dg.language(Some("de")), "de");
    }
}
