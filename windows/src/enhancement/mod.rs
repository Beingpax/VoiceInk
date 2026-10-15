//! LLM access for AI enhancement and Command Mode (port of
//! `AIEnhancementService` and the `LLMkit` chat clients).
//!
//! The pipeline depends only on the [`ChatModel`] trait. [`create`] builds
//! the client for a provider and wraps it in the [`RateLimited`] and
//! [`Retrying`] decorators, mirroring the macOS retry behaviour.

mod anthropic;
mod openai;
mod resilience;

pub use anthropic::AnthropicChat;
pub use openai::OpenAiChat;
pub use resilience::{RateLimited, RateLimiter, RetryPolicy, Retrying};

use crate::config::{EnhancementProvider, EnhancementSettings};
use crate::credentials::SecretStore;
use crate::http::HttpError;
use std::sync::Arc;
use std::time::Duration;

const MIN_TIMEOUT: Duration = Duration::from_secs(5);

#[derive(Debug, thiserror::Error)]
pub enum EnhancementError {
    #[error("{0}")]
    NotConfigured(String),
    #[error(transparent)]
    Http(#[from] HttpError),
    #[error("AI enhancement failed to process the text.")]
    EmptyResponse,
}

/// A chat-completion model with a fixed system prompt + user message shape.
pub trait ChatModel: Send + Sync {
    /// # Errors
    /// Returns [`EnhancementError`] when the request fails or yields no text.
    fn complete(&self, system: &str, user: &str) -> Result<String, EnhancementError>;
}

/// Whether `provider` has what it needs (API key or endpoint), like `isConfigured(for:)`.
pub fn is_configured(settings: &EnhancementSettings, provider: EnhancementProvider, secrets: &dyn SecretStore) -> bool {
    match provider {
        EnhancementProvider::Ollama => true,
        EnhancementProvider::Custom => !settings.custom_endpoint.trim().is_empty(),
        p => p.credential_key().is_some_and(|k| secrets.has(k)),
    }
}

/// Builds the client for `provider`/`model` with rate limiting and retries.
///
/// # Errors
/// Returns [`EnhancementError::NotConfigured`] when the provider lacks a key or endpoint.
pub fn create(
    settings: &EnhancementSettings,
    provider: EnhancementProvider,
    model: &str,
    secrets: &dyn SecretStore,
    limiter: &Arc<RateLimiter>,
) -> Result<Box<dyn ChatModel>, EnhancementError> {
    if !is_configured(settings, provider, secrets) {
        return Err(EnhancementError::NotConfigured(format!("no API key configured for {}", provider.display_name())));
    }
    let endpoint = settings.endpoint_for(provider);
    let api_key = provider.credential_key().and_then(|k| secrets.get(k));
    let timeout = Duration::from_secs(settings.timeout_secs).max(MIN_TIMEOUT);

    let mut client: Box<dyn ChatModel> = match provider {
        EnhancementProvider::Anthropic => {
            Box::new(AnthropicChat::new(endpoint, api_key.unwrap_or_default(), model.to_string(), timeout))
        }
        p => Box::new(OpenAiChat::new(p, endpoint, api_key, model.to_string(), timeout)),
    };
    if provider.is_rate_limited() {
        client = Box::new(RateLimited::new(client, Arc::clone(limiter)));
    }
    Ok(Box::new(Retrying::new(client, RetryPolicy::from_settings(settings))))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::credentials::MemoryStore;

    #[test]
    fn configuration_depends_on_keys_and_endpoints() {
        let settings = EnhancementSettings::default();
        let empty = MemoryStore::default();
        assert!(!is_configured(&settings, EnhancementProvider::OpenAI, &empty));
        assert!(is_configured(&settings, EnhancementProvider::Ollama, &empty));
        assert!(is_configured(&settings, EnhancementProvider::Custom, &empty));
        let keys = MemoryStore::with(&[("anthropic", "k")]);
        assert!(is_configured(&settings, EnhancementProvider::Anthropic, &keys));

        let limiter = Arc::new(RateLimiter::default());
        assert!(matches!(
            create(&settings, EnhancementProvider::OpenAI, "m", &empty, &limiter),
            Err(EnhancementError::NotConfigured(_))
        ));
        assert!(create(&settings, EnhancementProvider::Anthropic, "m", &keys, &limiter).is_ok());
    }
}
