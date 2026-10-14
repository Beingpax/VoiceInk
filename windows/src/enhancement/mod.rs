//! AI enhancement — port of `AIEnhancementService` and the LLMkit chat clients.

use crate::config::{EnhancementProvider, EnhancementSettings};
use crate::credentials;
use crate::http::{self, HttpError};
use crate::prompts::{build_system_message, build_user_message, CustomPrompt, PromptContext};
use crate::text::filter_enhancement_output;
use serde_json::json;
use std::sync::Mutex;
use std::time::{Duration, Instant};

#[derive(Debug)]
pub enum EnhancementError {
    NotConfigured(String),
    Http(HttpError),
    EmptyResponse,
}

impl std::fmt::Display for EnhancementError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NotConfigured(m) => write!(f, "{m}"),
            Self::Http(e) => write!(f, "{e}"),
            Self::EmptyResponse => write!(f, "AI enhancement failed to process the text."),
        }
    }
}

impl std::error::Error for EnhancementError {}

impl From<HttpError> for EnhancementError {
    fn from(e: HttpError) -> Self {
        Self::Http(e)
    }
}

#[derive(Debug, Clone)]
pub struct EnhancementResult {
    pub text: String,
    pub duration: Duration,
    pub prompt_name: String,
    pub model: String,
    pub system_message: String,
    pub user_message: String,
}

/// Resolved per-dictation enhancement configuration (global settings + mode overrides).
#[derive(Debug, Clone)]
pub struct EnhancementRequest<'a> {
    pub settings: &'a EnhancementSettings,
    pub provider: EnhancementProvider,
    pub model: String,
    pub prompt: &'a CustomPrompt,
    pub context: PromptContext<'a>,
}

/// Whether the provider has what it needs (API key / endpoint), like `isConfigured(for:)`.
pub fn is_configured(settings: &EnhancementSettings, provider: EnhancementProvider) -> bool {
    match provider {
        EnhancementProvider::Ollama => true,
        EnhancementProvider::Custom => !settings.custom_endpoint.trim().is_empty(),
        p => credentials::has(p.key_name()),
    }
}

static LAST_REQUEST: Mutex<Option<Instant>> = Mutex::new(None);
const RATE_LIMIT_INTERVAL: Duration = Duration::from_secs(1);

fn wait_for_rate_limit() {
    let mut last = LAST_REQUEST.lock().unwrap_or_else(|e| e.into_inner());
    if let Some(prev) = *last {
        let elapsed = prev.elapsed();
        if elapsed < RATE_LIMIT_INTERVAL {
            std::thread::sleep(RATE_LIMIT_INTERVAL - elapsed);
        }
    }
    *last = Some(Instant::now());
}

/// Enhances `text`, retrying transient failures with exponential backoff
/// (1 s, 2 s, ...) and timeouts immediately when `retry_on_timeout` is set.
pub fn enhance(
    text: &str,
    req: &EnhancementRequest<'_>,
) -> Result<EnhancementResult, EnhancementError> {
    let start = Instant::now();
    let system_message = build_system_message(req.prompt, &req.context);
    let user_message = build_user_message(text);

    if text.trim().is_empty() {
        return Ok(EnhancementResult {
            text: String::new(),
            duration: start.elapsed(),
            prompt_name: req.prompt.title.clone(),
            model: req.model.clone(),
            system_message,
            user_message,
        });
    }
    if !is_configured(req.settings, req.provider) {
        return Err(EnhancementError::NotConfigured(format!(
            "no API key configured for {}",
            req.provider.display_name()
        )));
    }

    let max_attempts = req.settings.max_attempts.max(1);
    let mut delay = Duration::from_secs(1);
    let mut attempt = 0;
    let output = loop {
        attempt += 1;
        if req.provider.is_rate_limited() {
            wait_for_rate_limit();
        }
        match complete(req, &system_message, &user_message) {
            Ok(out) => break out,
            Err(EnhancementError::Http(e)) if attempt < max_attempts && e.is_transient() => {
                log::warn!(
                    "enhancement failed ({e}), retrying in {delay:?} ({attempt}/{max_attempts})"
                );
                std::thread::sleep(delay);
                delay *= 2;
            }
            Err(EnhancementError::Http(HttpError::Timeout))
                if attempt < max_attempts && req.settings.retry_on_timeout =>
            {
                log::warn!("enhancement timed out, retrying ({attempt}/{max_attempts})");
            }
            Err(e) => return Err(e),
        }
    };

    let filtered = filter_enhancement_output(output.trim());
    if filtered.is_empty() && req.provider != EnhancementProvider::Ollama {
        return Err(EnhancementError::EmptyResponse);
    }
    Ok(EnhancementResult {
        text: filtered,
        duration: start.elapsed(),
        prompt_name: req.prompt.title.clone(),
        model: req.model.clone(),
        system_message,
        user_message,
    })
}

fn complete(
    req: &EnhancementRequest<'_>,
    system: &str,
    user: &str,
) -> Result<String, EnhancementError> {
    let timeout = Duration::from_secs(req.settings.timeout_secs.max(5));
    let agent = http::agent(timeout);
    let endpoint = req.settings.endpoint_for(req.provider);

    match req.provider {
        EnhancementProvider::Anthropic => {
            let key = credentials::get(req.provider.key_name()).unwrap_or_default();
            let body = anthropic_body(&req.model, system, user);
            let r = agent
                .post(&endpoint)
                .set("x-api-key", &key)
                .set("anthropic-version", "2023-06-01");
            let json = http::send_json(r, &body)?;
            parse_anthropic(&json).ok_or(EnhancementError::EmptyResponse)
        }
        provider => {
            let mut r = agent.post(&endpoint);
            if let Some(key) = credentials::get(provider.key_name()) {
                r = r.set("Authorization", &format!("Bearer {key}"));
            }
            if provider == EnhancementProvider::OpenRouter {
                r = r
                    .set("HTTP-Referer", "https://tryvoiceink.com")
                    .set("X-Title", "VoiceInk");
            }
            let body = openai_body(provider, &req.model, system, user);
            let json = http::send_json(r, &body)?;
            parse_openai(&json).ok_or(EnhancementError::EmptyResponse)
        }
    }
}

pub(crate) fn openai_body(
    provider: EnhancementProvider,
    model: &str,
    system: &str,
    user: &str,
) -> serde_json::Value {
    let mut body = json!({
        "model": model,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        "stream": false,
    });
    // Reasoning-capable OpenAI models reject `temperature`; everyone else gets a low one.
    if provider != EnhancementProvider::OpenAI {
        body["temperature"] = json!(0.3);
    }
    body
}

pub(crate) fn anthropic_body(model: &str, system: &str, user: &str) -> serde_json::Value {
    json!({
        "model": model,
        "max_tokens": 8192,
        "system": system,
        "messages": [{"role": "user", "content": user}],
    })
}

pub(crate) fn parse_openai(json: &serde_json::Value) -> Option<String> {
    let content = json.pointer("/choices/0/message/content")?;
    match content {
        serde_json::Value::String(s) => Some(s.clone()),
        // Some servers return content parts.
        serde_json::Value::Array(parts) => Some(
            parts
                .iter()
                .filter_map(|p| p.get("text").and_then(|t| t.as_str()))
                .collect::<Vec<_>>()
                .join(""),
        ),
        _ => None,
    }
}

pub(crate) fn parse_anthropic(json: &serde_json::Value) -> Option<String> {
    let blocks = json.get("content")?.as_array()?;
    let text: String = blocks
        .iter()
        .filter(|b| b.get("type").and_then(|t| t.as_str()) == Some("text"))
        .filter_map(|b| b.get("text").and_then(|t| t.as_str()))
        .collect();
    Some(text)
}

impl EnhancementSettings {
    /// Endpoint for an arbitrary provider (modes can override the provider).
    pub fn endpoint_for(&self, provider: EnhancementProvider) -> String {
        let mut s = self.clone();
        s.provider = provider;
        s.endpoint()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builds_openai_body() {
        let b = openai_body(EnhancementProvider::Groq, "m", "sys", "usr");
        assert_eq!(b["messages"][0]["role"], "system");
        assert_eq!(b["messages"][1]["content"], "usr");
        assert_eq!(b["temperature"], 0.3);
        let b = openai_body(EnhancementProvider::OpenAI, "m", "s", "u");
        assert!(b.get("temperature").is_none());
    }

    #[test]
    fn parses_responses() {
        let o = json!({"choices": [{"message": {"content": "hi"}}]});
        assert_eq!(parse_openai(&o).as_deref(), Some("hi"));
        let a = json!({"content": [{"type": "thinking", "thinking": "x"}, {"type": "text", "text": "yo"}]});
        assert_eq!(parse_anthropic(&a).as_deref(), Some("yo"));
        assert_eq!(parse_openai(&json!({})), None);
    }

    #[test]
    fn anthropic_body_shape() {
        let b = anthropic_body("claude", "s", "u");
        assert_eq!(b["system"], "s");
        assert_eq!(b["messages"][0]["role"], "user");
    }
}
