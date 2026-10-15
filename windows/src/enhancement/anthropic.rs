//! Anthropic Messages API client.

use super::{ChatModel, EnhancementError};
use crate::http;
use serde_json::{Value, json};
use std::time::Duration;

const API_VERSION: &str = "2023-06-01";
const MAX_TOKENS: u32 = 8192;

pub struct AnthropicChat {
    endpoint: String,
    api_key: String,
    model: String,
    timeout: Duration,
}

impl AnthropicChat {
    pub fn new(endpoint: String, api_key: String, model: String, timeout: Duration) -> Self {
        Self { endpoint, api_key, model, timeout }
    }

    fn body(&self, system: &str, user: &str) -> Value {
        json!({
            "model": self.model,
            "max_tokens": MAX_TOKENS,
            "system": system,
            "messages": [{"role": "user", "content": user}],
        })
    }
}

/// Joins the `text` blocks, skipping thinking blocks.
fn parse(json: &Value) -> Option<String> {
    let blocks = json.get("content")?.as_array()?;
    Some(
        blocks
            .iter()
            .filter(|b| b.get("type").and_then(Value::as_str) == Some("text"))
            .filter_map(|b| b.get("text").and_then(Value::as_str))
            .collect(),
    )
}

impl ChatModel for AnthropicChat {
    fn complete(&self, system: &str, user: &str) -> Result<String, EnhancementError> {
        let req = http::agent(self.timeout)
            .post(&self.endpoint)
            .set("x-api-key", &self.api_key)
            .set("anthropic-version", API_VERSION);
        let json = http::send_json(req, &self.body(system, user))?;
        parse(&json).ok_or(EnhancementError::EmptyResponse)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn body_and_parsing() {
        let chat = AnthropicChat::new(String::new(), String::new(), "claude".into(), Duration::from_secs(1));
        let b = chat.body("s", "u");
        assert_eq!(b["system"], "s");
        assert_eq!(b["messages"][0]["role"], "user");
        let answer = json!({"content": [{"type": "thinking", "thinking": "x"}, {"type": "text", "text": "yo"}]});
        assert_eq!(parse(&answer).as_deref(), Some("yo"));
    }
}
