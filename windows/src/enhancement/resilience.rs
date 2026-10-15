//! Retry and rate-limit decorators for [`ChatModel`]s (port of
//! `makeRequestWithRetry` and `waitForRateLimit`).

use super::{ChatModel, EnhancementError};
use crate::config::EnhancementSettings;
use crate::http::HttpError;
use std::sync::{Arc, Mutex, PoisonError};
use std::time::{Duration, Instant};

/// Spaces requests at least `interval` apart across all models sharing it.
#[derive(Debug)]
pub struct RateLimiter {
    interval: Duration,
    last: Mutex<Option<Instant>>,
}

impl RateLimiter {
    pub const DEFAULT_INTERVAL: Duration = Duration::from_secs(1);

    pub fn new(interval: Duration) -> Self {
        Self { interval, last: Mutex::new(None) }
    }

    /// Blocks until the next request may be sent.
    pub fn wait(&self) {
        let mut last = self.last.lock().unwrap_or_else(PoisonError::into_inner);
        if let Some(remaining) = last.and_then(|t| self.interval.checked_sub(t.elapsed())) {
            std::thread::sleep(remaining);
        }
        *last = Some(Instant::now());
    }
}

impl Default for RateLimiter {
    fn default() -> Self {
        Self::new(Self::DEFAULT_INTERVAL)
    }
}

pub struct RateLimited {
    inner: Box<dyn ChatModel>,
    limiter: Arc<RateLimiter>,
}

impl RateLimited {
    pub fn new(inner: Box<dyn ChatModel>, limiter: Arc<RateLimiter>) -> Self {
        Self { inner, limiter }
    }
}

impl ChatModel for RateLimited {
    fn complete(&self, system: &str, user: &str) -> Result<String, EnhancementError> {
        self.limiter.wait();
        self.inner.complete(system, user)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RetryPolicy {
    pub max_attempts: u32,
    /// Timeouts are retried immediately (no backoff) when set.
    pub retry_on_timeout: bool,
    /// First backoff for transient errors; doubles after every attempt.
    pub initial_backoff: Duration,
}

impl RetryPolicy {
    pub const INITIAL_BACKOFF: Duration = Duration::from_secs(1);

    pub fn from_settings(settings: &EnhancementSettings) -> Self {
        Self {
            max_attempts: settings.max_attempts.max(1),
            retry_on_timeout: settings.retry_on_timeout,
            initial_backoff: Self::INITIAL_BACKOFF,
        }
    }
}

pub struct Retrying {
    inner: Box<dyn ChatModel>,
    policy: RetryPolicy,
}

impl Retrying {
    pub fn new(inner: Box<dyn ChatModel>, policy: RetryPolicy) -> Self {
        Self { inner, policy }
    }
}

impl ChatModel for Retrying {
    fn complete(&self, system: &str, user: &str) -> Result<String, EnhancementError> {
        let max = self.policy.max_attempts.max(1);
        let mut backoff = self.policy.initial_backoff;
        let mut attempt = 1;
        loop {
            match self.inner.complete(system, user) {
                Err(EnhancementError::Http(e)) if attempt < max && e.is_transient() => {
                    log::warn!("AI request failed ({e}), retrying in {backoff:?} ({attempt}/{max})");
                    std::thread::sleep(backoff);
                    backoff *= 2;
                }
                Err(EnhancementError::Http(HttpError::Timeout)) if attempt < max && self.policy.retry_on_timeout => {
                    log::warn!("AI request timed out, retrying ({attempt}/{max})");
                }
                result => return result,
            }
            attempt += 1;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU32, Ordering};

    /// Fails with the given errors in order, then succeeds.
    struct Flaky {
        failures: Mutex<Vec<HttpError>>,
        calls: AtomicU32,
    }

    impl Flaky {
        fn new(failures: Vec<HttpError>) -> Self {
            Self { failures: Mutex::new(failures), calls: AtomicU32::new(0) }
        }
    }

    impl ChatModel for Arc<Flaky> {
        fn complete(&self, _: &str, _: &str) -> Result<String, EnhancementError> {
            self.calls.fetch_add(1, Ordering::SeqCst);
            let mut failures = self.failures.lock().unwrap();
            if failures.is_empty() { Ok("ok".into()) } else { Err(failures.remove(0).into()) }
        }
    }

    fn policy(max_attempts: u32, retry_on_timeout: bool) -> RetryPolicy {
        RetryPolicy { max_attempts, retry_on_timeout, initial_backoff: Duration::from_millis(1) }
    }

    fn status(code: u16) -> HttpError {
        HttpError::Status { code, body: String::new() }
    }

    #[test]
    fn retries_transient_errors_until_success() {
        let flaky = Arc::new(Flaky::new(vec![status(503), status(429)]));
        let model = Retrying::new(Box::new(Arc::clone(&flaky)), policy(3, false));
        assert_eq!(model.complete("s", "u").unwrap(), "ok");
        assert_eq!(flaky.calls.load(Ordering::SeqCst), 3);
    }

    #[test]
    fn gives_up_after_max_attempts_and_on_permanent_errors() {
        let flaky = Arc::new(Flaky::new(vec![status(500), status(500)]));
        let model = Retrying::new(Box::new(Arc::clone(&flaky)), policy(2, false));
        assert!(model.complete("s", "u").is_err());
        assert_eq!(flaky.calls.load(Ordering::SeqCst), 2);

        let flaky = Arc::new(Flaky::new(vec![status(400)]));
        let model = Retrying::new(Box::new(Arc::clone(&flaky)), policy(3, false));
        assert!(model.complete("s", "u").is_err());
        assert_eq!(flaky.calls.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn timeouts_retry_only_when_enabled() {
        let flaky = Arc::new(Flaky::new(vec![HttpError::Timeout]));
        assert!(Retrying::new(Box::new(Arc::clone(&flaky)), policy(3, false)).complete("s", "u").is_err());
        let flaky = Arc::new(Flaky::new(vec![HttpError::Timeout]));
        assert!(Retrying::new(Box::new(Arc::clone(&flaky)), policy(3, true)).complete("s", "u").is_ok());
    }

    #[test]
    fn rate_limiter_spaces_requests() {
        let limiter = RateLimiter::new(Duration::from_millis(30));
        let start = Instant::now();
        limiter.wait();
        limiter.wait();
        assert!(start.elapsed() >= Duration::from_millis(30));
    }
}
