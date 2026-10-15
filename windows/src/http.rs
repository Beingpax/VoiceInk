//! Shared HTTP plumbing: agent construction, multipart bodies and error mapping.
//!
//! On Windows TLS goes through `SChannel` (`native-tls`) so the system
//! certificate store and corporate proxies/inspection roots just work.

use std::time::Duration;

/// Bodies above this many characters are shortened in error messages.
const MAX_ERROR_BODY_CHARS: usize = 300;
const CONNECT_TIMEOUT: Duration = Duration::from_secs(15);

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum HttpError {
    /// Non-2xx response.
    #[error("{}", describe_status(*code, body))]
    Status { code: u16, body: String },
    #[error("the request timed out")]
    Timeout,
    /// DNS, connect, TLS or I/O failure.
    #[error("network error: {0}")]
    Network(String),
    #[error("unexpected response: {0}")]
    Decode(String),
}

impl HttpError {
    /// Errors worth retrying with backoff (mirrors `makeRequestWithRetry`).
    pub fn is_transient(&self) -> bool {
        match self {
            HttpError::Network(_) => true,
            HttpError::Status { code, .. } => *code == 429 || (500..=599).contains(code),
            HttpError::Timeout | HttpError::Decode(_) => false,
        }
    }
}

fn describe_status(code: u16, body: &str) -> String {
    match code {
        401 | 403 => "authentication failed — check the API key".to_string(),
        429 => "rate limit exceeded".to_string(),
        _ => format!("HTTP {code}: {}", summarize_error_body(body)),
    }
}

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
            return m.as_str().map_or_else(|| m.to_string(), str::to_string);
        }
    }
    let trimmed = body.trim();
    if trimmed.chars().count() > MAX_ERROR_BODY_CHARS {
        format!("{}…", trimmed.chars().take(MAX_ERROR_BODY_CHARS).collect::<String>())
    } else {
        trimmed.to_string()
    }
}

pub fn agent(timeout: Duration) -> ureq::Agent {
    let builder = ureq::AgentBuilder::new()
        .timeout_connect(CONNECT_TIMEOUT)
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
        ureq::Error::Status(code, resp) => HttpError::Status { code, body: resp.into_string().unwrap_or_default() },
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
///
/// # Errors
/// Returns [`HttpError`] for transport failures, non-2xx statuses and
/// responses that are not JSON.
pub fn send_bytes(req: ureq::Request, body: &[u8]) -> Result<serde_json::Value, HttpError> {
    let resp = req.send_bytes(body).map_err(map_error)?;
    let text = resp.into_string().map_err(|e| HttpError::Network(e.to_string()))?;
    serde_json::from_str(&text).map_err(|e| HttpError::Decode(format!("{e}: {}", summarize_error_body(&text))))
}

/// Sends `body` as JSON and parses the JSON response.
///
/// # Errors
/// See [`send_bytes`].
pub fn send_json(req: ureq::Request, body: &serde_json::Value) -> Result<serde_json::Value, HttpError> {
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
    #[must_use]
    pub fn new() -> Self {
        Self { boundary: format!("VoiceInkBoundary{}", uuid::Uuid::new_v4().simple()), body: Vec::new() }
    }

    #[must_use]
    pub fn text(mut self, name: &str, value: &str) -> Self {
        self.body.extend_from_slice(
            format!("--{}\r\nContent-Disposition: form-data; name=\"{}\"\r\n\r\n{}\r\n", self.boundary, name, value)
                .as_bytes(),
        );
        self
    }

    #[must_use]
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
        self.body.extend_from_slice(format!("--{}--\r\n", self.boundary).as_bytes());
        (self.content_type(), self.body)
    }
}

/// A minimal blocking HTTP/1.1 server for client tests: answers each request
/// path with a canned `(status, body)` and records what it received.
#[cfg(test)]
pub mod test_server {
    use std::io::{BufRead, BufReader, Read, Write};
    use std::thread::JoinHandle;

    pub struct Route {
        pub path: &'static str,
        pub status: u16,
        pub body: &'static str,
    }

    /// Serves one request per route (in any order) and returns the base URL and
    /// a handle yielding `"<path> <body>"` for every request.
    ///
    /// # Panics
    /// When the local socket cannot be opened (test environment broken).
    pub fn serve(routes: Vec<Route>) -> (String, JoinHandle<Vec<String>>) {
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let handle = std::thread::spawn(move || {
            let mut seen = Vec::new();
            for _ in 0..routes.len() {
                let (mut stream, _) = listener.accept().unwrap();
                let mut reader = BufReader::new(stream.try_clone().unwrap());
                let mut request_line = String::new();
                reader.read_line(&mut request_line).unwrap();
                let mut len = 0usize;
                loop {
                    let mut line = String::new();
                    reader.read_line(&mut line).unwrap();
                    if line.trim().is_empty() {
                        break;
                    }
                    if let Some(v) = line.to_ascii_lowercase().strip_prefix("content-length:") {
                        len = v.trim().parse().unwrap();
                    }
                }
                let mut body = vec![0u8; len];
                reader.read_exact(&mut body).unwrap();
                let path = request_line.split_whitespace().nth(1).unwrap().to_string();
                let route = routes.iter().find(|r| r.path == path).expect("unexpected path");
                seen.push(format!("{path} {}", String::from_utf8_lossy(&body)));
                let resp = format!(
                    "HTTP/1.1 {} X\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                    route.status,
                    route.body.len(),
                    route.body
                );
                stream.write_all(resp.as_bytes()).unwrap();
            }
            seen
        });
        (base, handle)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn multipart_layout() {
        let mp = Multipart::new().text("model", "m").file("file", "a.wav", "audio/wav", b"RIFF");
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
        assert_eq!(summarize_error_body(r#"{"error":{"message":"bad key"}}"#), "bad key");
        assert_eq!(summarize_error_body("plain"), "plain");
        assert_eq!(
            HttpError::Status { code: 401, body: String::new() }.to_string(),
            "authentication failed — check the API key"
        );
        assert!(HttpError::Status { code: 503, body: String::new() }.is_transient());
        assert!(!HttpError::Status { code: 400, body: String::new() }.is_transient());
    }
}
