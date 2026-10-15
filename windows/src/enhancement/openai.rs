//! OpenAI-compatible `/chat/completions` client (`OpenAI`, Groq, Gemini,
//! Cerebras, Mistral, `OpenRouter`, Ollama, custom servers).

use super::{ChatModel, EnhancementError};
use crate::config::EnhancementProvider;
use crate::http;
use serde_json::{Value, json};
use std::time::Duration;

/// Low but non-zero temperature keeps clean-up faithful without being robotic.
const TEMPERATURE: f64 = 0.3;

pub struct OpenAiChat {
    provider: EnhancementProvider,
    endpoint: String,
    api_key: Option<String>,
    model: String,
    timeout: Duration,
}

impl OpenAiChat {
    pub fn new(
        provider: EnhancementProvider,
        endpoint: String,
        api_key: Option<String>,
        model: String,
        timeout: Duration,
    ) -> Self {
        Self { provider, endpoint, api_key, model, timeout }
    }

    fn body(&self, system: &str, user: &str) -> Value {
        let mut body = json!({
            "model": self.model,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "stream": false,
        });
        // Reasoning-capable OpenAI models reject `temperature`.
        if self.provider != EnhancementProvider::OpenAI {
            body["temperature"] = json!(TEMPERATURE);
        }
        body
    }
}

/// Extracts the answer; some servers return a list of content parts.
fn parse(json: &Value) -> Option<String> {
    match json.pointer("/choices/0/message/content")? {
        Value::String(s) => Some(s.clone()),
        Value::Array(parts) => Some(parts.iter().filter_map(|p| p.get("text").and_then(Value::as_str)).collect()),
        _ => None,
    }
}

impl ChatModel for OpenAiChat {
    fn complete(&self, system: &str, user: &str) -> Result<String, EnhancementError> {
        let mut req = http::agent(self.timeout).post(&self.endpoint);
        if let Some(key) = &self.api_key {
            req = req.set("Authorization", &format!("Bearer {key}"));
        }
        if self.provider == EnhancementProvider::OpenRouter {
            req = req.set("HTTP-Referer", "https://tryvoiceink.com").set("X-Title", "VoiceInk");
        }
        let json = http::send_json(req, &self.body(system, user))?;
        parse(&json).ok_or(EnhancementError::EmptyResponse)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::http::test_server::{Route, serve};

    fn client(provider: EnhancementProvider, endpoint: String) -> OpenAiChat {
        OpenAiChat::new(provider, endpoint, Some("sk".into()), "m".into(), Duration::from_secs(5))
    }

    #[test]
    fn body_shape_and_temperature() {
        let groq = client(EnhancementProvider::Groq, String::new()).body("sys", "usr");
        assert_eq!(groq["messages"][0]["role"], "system");
        assert_eq!(groq["messages"][1]["content"], "usr");
        assert_eq!(groq["temperature"], TEMPERATURE);
        assert!(client(EnhancementProvider::OpenAI, String::new()).body("s", "u").get("temperature").is_none());
    }

    #[test]
    fn parses_string_and_part_content() {
        assert_eq!(parse(&json!({"choices": [{"message": {"content": "hi"}}]})).as_deref(), Some("hi"));
        let parts = json!({"choices": [{"message": {"content": [{"text": "a"}, {"text": "b"}]}}]});
        assert_eq!(parse(&parts).as_deref(), Some("ab"));
        assert_eq!(parse(&json!({})), None);
    }

    #[test]
    fn round_trip_against_server() {
        let (base, server) = serve(vec![Route {
            path: "/v1/chat/completions",
            status: 200,
            body: r#"{"choices":[{"message":{"content":"Done."}}]}"#,
        }]);
        let chat = client(EnhancementProvider::Custom, format!("{base}/v1/chat/completions"));
        assert_eq!(chat.complete("sys", "usr").unwrap(), "Done.");
        assert!(server.join().unwrap()[0].contains(r#""content":"usr""#));
    }
}
