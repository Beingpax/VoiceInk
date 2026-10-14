//! Shared HTTP plumbing: agent construction, multipart bodies and error mapping.
//!
//! On Windows TLS goes through SChannel (`native-tls`) so the system
//! certificate store and corporate proxies/inspection roots just work.

use std::time::Duration;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum HttpError {
    /// Non-2xx response.
    Status {
        code: u16,
        body: String,
    },
    Timeout,
    /// DNS, connect, TLS or I/O failure.
    Network(String),
    Decode(String),
}

impl HttpError {
    /// Errors worth retrying with backoff (mirrors `makeRequestWithRetry`).
    pub fn is_transient(&self) -> bool {
        match self {
            HttpError::Network(_) => true,
            HttpError::Status { code, .. } => *code == 429 || (500..=599).contains(code),
            _ => false,
        }
    }
}

impl std::fmt::Display for HttpError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            HttpError::Status { code: 401, .. } | HttpError::Status { code: 403, .. } => {
                write!(f, "authentication failed — check the API key")
            }
            HttpError::Status { code: 429, .. } => write!(f, "rate limit exceeded"),
            HttpError::Status { code, body } => {
                write!(f, "HTTP {code}: {}", summarize_error_body(body))
            }
            HttpError::Timeout => write!(f, "the request timed out"),
            HttpError::Network(e) => write!(f, "network error: {e}"),
            HttpError::Decode(e) => write!(f, "unexpected response: {e}"),
        }
    }
}

impl std::error::Error for HttpError {}

/// Pulls `error.message` (OpenAI/Anthropic/Groq style) out of an error body.
pub fn summarize_error_body(body: &str) -> String {
    if let Ok(v) = serde_json::from_str::<serde_json::Value>(body) {
        let msg = v
            .pointer("/error/message")
            .or_else(|| v.pointer("/detail/message"))
            .or_else(|| v.get("message"))
            .or_else(|| v.get("err_msg"))
            .or_else(|| v.get("detail"))
            .or_else(|| v.get("error"));
        if let Some(m) = msg {
            return m
                .as_str()
                .map(str::to_string)
                .unwrap_or_else(|| m.to_string());
        }
    }
    let trimmed = body.trim();
    if trimmed.chars().count() > 300 {
        format!("{}…", trimmed.chars().take(300).collect::<String>())
    } else {
        trimmed.to_string()
    }
}

pub fn agent(timeout: Duration) -> ureq::Agent {
    let builder = ureq::AgentBuilder::new()
        .timeout_connect(Duration::from_secs(15))
        .timeout(timeout)
        .user_agent(concat!("VoiceInk-Windows/", env!("CARGO_PKG_VERSION")));
    #[cfg(windows)]
    let builder = match native_tls::TlsConnector::new() {
        Ok(tls) => builder.tls_connector(std::sync::Arc::new(tls)),
        Err(e) => {
            log::error!("native TLS unavailable: {e}");
            builder
        }
    };
    builder.build()
}

fn map_error(err: ureq::Error) -> HttpError {
    match err {
        ureq::Error::Status(code, resp) => HttpError::Status {
            code,
            body: resp.into_string().unwrap_or_default(),
        },
        ureq::Error::Transport(t) => {
            let text = t.to_string();
            let lower = text.to_ascii_lowercase();
            if lower.contains("timed out") || lower.contains("timeout") {
                HttpError::Timeout
            } else {
                HttpError::Network(text)
            }
        }
    }
}

/// Sends a request with a raw body and parses the JSON response.
pub fn send_bytes(req: ureq::Request, body: &[u8]) -> Result<serde_json::Value, HttpError> {
    let resp = req.send_bytes(body).map_err(map_error)?;
    let text = resp
        .into_string()
        .map_err(|e| HttpError::Network(e.to_string()))?;
    serde_json::from_str(&text)
        .map_err(|e| HttpError::Decode(format!("{e}: {}", summarize_error_body(&text))))
}

pub fn send_json(
    req: ureq::Request,
    body: &serde_json::Value,
) -> Result<serde_json::Value, HttpError> {
    let bytes = serde_json::to_vec(body).map_err(|e| HttpError::Decode(e.to_string()))?;
    send_bytes(req.set("Content-Type", "application/json"), &bytes)
}

/// Builder for `multipart/form-data` bodies.
pub struct Multipart {
    boundary: String,
    body: Vec<u8>,
}

impl Default for Multipart {
    fn default() -> Self {
        Self::new()
    }
}

impl Multipart {
    pub fn new() -> Self {
        Self {
            boundary: format!("VoiceInkBoundary{}", uuid::Uuid::new_v4().simple()),
            body: Vec::new(),
        }
    }

    pub fn text(mut self, name: &str, value: &str) -> Self {
        self.body.extend_from_slice(
            format!(
                "--{}\r\nContent-Disposition: form-data; name=\"{}\"\r\n\r\n{}\r\n",
                self.boundary, name, value
            )
            .as_bytes(),
        );
        self
    }

    pub fn file(mut self, name: &str, filename: &str, content_type: &str, data: &[u8]) -> Self {
        self.body.extend_from_slice(
            format!(
                "--{}\r\nContent-Disposition: form-data; name=\"{}\"; filename=\"{}\"\r\nContent-Type: {}\r\n\r\n",
                self.boundary, name, filename, content_type
            )
            .as_bytes(),
        );
        self.body.extend_from_slice(data);
        self.body.extend_from_slice(b"\r\n");
        self
    }

    pub fn content_type(&self) -> String {
        format!("multipart/form-data; boundary={}", self.boundary)
    }

    pub fn finish(mut self) -> (String, Vec<u8>) {
        self.body
            .extend_from_slice(format!("--{}--\r\n", self.boundary).as_bytes());
        (self.content_type(), self.body)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn multipart_layout() {
        let mp = Multipart::new()
            .text("model", "m")
            .file("file", "a.wav", "audio/wav", b"RIFF");
        let (ct, body) = mp.finish();
        let boundary = ct.split("boundary=").nth(1).unwrap();
        let text = String::from_utf8(body).unwrap();
        assert!(text.starts_with(&format!("--{boundary}\r\n")));
        assert!(text.contains("name=\"model\"\r\n\r\nm\r\n"));
        assert!(text.contains("filename=\"a.wav\"\r\nContent-Type: audio/wav\r\n\r\nRIFF\r\n"));
        assert!(text.ends_with(&format!("--{boundary}--\r\n")));
    }

    #[test]
    fn summarizes_errors() {
        assert_eq!(
            summarize_error_body(r#"{"error":{"message":"bad key"}}"#),
            "bad key"
        );
        assert_eq!(summarize_error_body("plain"), "plain");
        assert!(HttpError::Status {
            code: 503,
            body: String::new()
        }
        .is_transient());
        assert!(!HttpError::Status {
            code: 400,
            body: String::new()
        }
        .is_transient());
    }
}
