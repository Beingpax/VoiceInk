//! Locations of everything `VoiceInk` stores on disk.
//!
//! All files live in one data directory (`%APPDATA%\VoiceInk` on Windows).
//! Code receives an [`AppPaths`] instead of computing paths itself, so tests
//! can point it at a temporary directory.

use std::path::{Path, PathBuf};

/// Overrides the data directory (useful for portable installs and tests).
pub const HOME_ENV_VAR: &str = "VOICEINK_HOME";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AppPaths {
    root: PathBuf,
}

impl AppPaths {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    /// `$VOICEINK_HOME`, else `%APPDATA%\VoiceInk` (or `$XDG_CONFIG_HOME/VoiceInk`
    /// / `~/.config/VoiceInk` when developing on other systems).
    pub fn detect() -> Self {
        if let Some(dir) = std::env::var_os(HOME_ENV_VAR) {
            return Self::new(dir);
        }
        let base = std::env::var_os("APPDATA")
            .or_else(|| std::env::var_os("XDG_CONFIG_HOME"))
            .map(PathBuf::from)
            .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))
            .unwrap_or_else(|| PathBuf::from("."));
        Self::new(base.join(crate::APP_NAME))
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn config(&self) -> PathBuf {
        self.root.join("config.json")
    }

    pub fn credentials(&self) -> PathBuf {
        self.root.join("keys.json")
    }

    pub fn history(&self) -> PathBuf {
        self.root.join("history.jsonl")
    }

    pub fn history_csv(&self) -> PathBuf {
        self.root.join("history.csv")
    }

    pub fn recordings(&self) -> PathBuf {
        self.root.join("recordings")
    }

    pub fn models(&self) -> PathBuf {
        self.root.join("models")
    }

    pub fn log(&self) -> PathBuf {
        self.root.join("voiceink.log")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn files_live_in_the_root() {
        let paths = AppPaths::new("/data/VoiceInk");
        assert_eq!(paths.config(), Path::new("/data/VoiceInk/config.json"));
        assert_eq!(paths.history(), Path::new("/data/VoiceInk/history.jsonl"));
        assert_eq!(paths.recordings(), Path::new("/data/VoiceInk/recordings"));
    }
}
