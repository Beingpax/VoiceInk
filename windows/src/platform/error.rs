//! Error type for the Win32 layer.

/// Something the operating system refused, or a user-facing explanation.
#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("{context}: {source}")]
    Win32 {
        context: &'static str,
        #[source]
        source: windows::core::Error,
    },
    /// A complete, user-facing message (e.g. "microphone access is blocked").
    #[error("{0}")]
    Message(String),
}

pub type Result<T> = std::result::Result<T, Error>;

/// Adds a short description of the failed operation to Win32 errors.
pub trait Context<T> {
    /// # Errors
    /// Wraps the original error in [`Error::Win32`].
    fn context(self, context: &'static str) -> Result<T>;
}

impl<T> Context<T> for windows::core::Result<T> {
    fn context(self, context: &'static str) -> Result<T> {
        self.map_err(|source| Error::Win32 { context, source })
    }
}

impl From<String> for Error {
    fn from(message: String) -> Self {
        Self::Message(message)
    }
}

impl From<&str> for Error {
    fn from(message: &str) -> Self {
        Self::Message(message.to_string())
    }
}
