//! User configuration, persisted as pretty JSON in `%APPDATA%\\VoiceInk\\config.json`.
//!
//! This replaces the `UserDefaults` keys scattered through the macOS app with a
//! single typed document that users can also edit by hand. Every field has a
//! default so older files keep loading after new options are added.

mod change;
mod providers;
mod sections;

pub use change::SettingChange;
pub use providers::{EnhancementProvider, LANGUAGES, TranscriptionProvider, credential_keys};
pub use sections::*;

use crate::prompts::{self, CustomPrompt};
use crate::text::{DEFAULT_FILLER_WORDS, Snippet, WordReplacement};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct Config {
    pub hotkeys: HotkeySettings,
    pub transcription: TranscriptionSettings,
    pub enhancement: EnhancementSettings,
    pub command: CommandSettings,
    pub output: OutputSettings,
    pub audio: AudioSettings,
    pub history: HistorySettings,
    pub overlay: OverlayPosition,
    pub start_with_windows: bool,
    pub prompts: Vec<CustomPrompt>,
    pub filler_words: Vec<String>,
    /// Custom vocabulary passed to the AI (and to Deepgram/ElevenLabs as keyterms).
    pub vocabulary: Vec<String>,
    pub replacements: Vec<WordReplacement>,
    /// Voice shortcuts expanded to saved text.
    pub snippets: Vec<Snippet>,
    pub modes: Vec<ModeConfig>,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            hotkeys: HotkeySettings::default(),
            transcription: TranscriptionSettings::default(),
            enhancement: EnhancementSettings::default(),
            command: CommandSettings::default(),
            output: OutputSettings::default(),
            audio: AudioSettings::default(),
            history: HistorySettings::default(),
            overlay: OverlayPosition::BottomCenter,
            start_with_windows: false,
            prompts: prompts::seed_prompts(),
            filler_words: DEFAULT_FILLER_WORDS.iter().map(ToString::to_string).collect(),
            vocabulary: Vec::new(),
            replacements: Vec::new(),
            snippets: Vec::new(),
            modes: Vec::new(),
        }
    }
}

/// Failure to read or write the configuration file.
#[derive(Debug, thiserror::Error)]
pub enum ConfigError {
    #[error("cannot access {path}: {source}")]
    Io {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("{path} is not valid settings JSON: {source}")]
    Parse {
        path: PathBuf,
        #[source]
        source: serde_json::Error,
    },
}

impl ConfigError {
    fn io(path: &Path, source: std::io::Error) -> Self {
        Self::Io { path: path.to_path_buf(), source }
    }
}

impl Config {
    pub fn prompt(&self, id: &str) -> Option<&CustomPrompt> {
        self.prompts.iter().find(|p| p.id == id)
    }

    /// Selected prompt, falling back to the global prompt and then the first
    /// prompt (like `repairModePromptSelections` on macOS).
    pub fn active_prompt(&self, id: Option<&str>) -> Option<&CustomPrompt> {
        id.and_then(|id| self.prompt(id))
            .or_else(|| self.prompt(&self.enhancement.prompt_id))
            .or_else(|| self.prompts.first())
    }

    /// Loads the configuration, creating the file with defaults on first run.
    ///
    /// # Errors
    /// Returns [`ConfigError`] when the file cannot be read or written, or
    /// contains invalid JSON.
    pub fn load(path: &Path) -> Result<Self, ConfigError> {
        match std::fs::read_to_string(path) {
            Ok(text) => {
                let mut cfg: Config = serde_json::from_str(&text)
                    .map_err(|source| ConfigError::Parse { path: path.to_path_buf(), source })?;
                if cfg.prompts.is_empty() {
                    cfg.prompts = prompts::seed_prompts();
                }
                Ok(cfg)
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                let cfg = Config::default();
                cfg.save(path)?;
                Ok(cfg)
            }
            Err(e) => Err(ConfigError::io(path, e)),
        }
    }

    /// Writes the configuration atomically (write to a temp file, then rename),
    /// so a crash never leaves a truncated file behind.
    ///
    /// # Errors
    /// Returns [`ConfigError::Io`] when the file cannot be written.
    pub fn save(&self, path: &Path) -> Result<(), ConfigError> {
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir).map_err(|e| ConfigError::io(dir, e))?;
        }
        let json = serde_json::to_string_pretty(self)
            .map_err(|source| ConfigError::Parse { path: path.to_path_buf(), source })?;
        let tmp = path.with_extension("json.tmp");
        std::fs::write(&tmp, json).map_err(|e| ConfigError::io(&tmp, e))?;
        std::fs::rename(&tmp, path).map_err(|e| ConfigError::io(path, e))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_config_round_trips() {
        let cfg = Config::default();
        let json = serde_json::to_string(&cfg).unwrap();
        let back: Config = serde_json::from_str(&json).unwrap();
        assert_eq!(cfg, back);
    }

    #[test]
    fn partial_config_fills_defaults() {
        let cfg: Config =
            serde_json::from_str(r#"{"transcription": {"provider": "deepgram"}, "enhancement": {"enabled": true}}"#)
                .unwrap();
        assert_eq!(cfg.transcription.provider, TranscriptionProvider::Deepgram);
        assert_eq!(cfg.transcription.model_name(), "nova-3");
        assert!(cfg.enhancement.enabled);
        assert_eq!(cfg.prompts.len(), 5);
        assert_eq!(cfg.hotkeys.record, "RightCtrl");
    }

    #[test]
    fn openai_is_the_default_everywhere() {
        let cfg = Config::default();
        assert_eq!(cfg.transcription.provider, TranscriptionProvider::OpenAI);
        assert_eq!(cfg.transcription.model_name(), "gpt-4o-transcribe");
        assert_eq!(cfg.enhancement.provider, EnhancementProvider::OpenAI);
        // One OpenAI key covers both transcription and enhancement.
        assert_eq!(TranscriptionProvider::OpenAI.credential_key(), EnhancementProvider::OpenAI.credential_key());
        assert_eq!(TranscriptionProvider::Local.credential_key(), None);
        assert!(credential_keys().windows(2).all(|w| w[0] < w[1]));
    }

    #[test]
    fn command_falls_back_to_enhancement_model() {
        let mut cfg = Config::default();
        cfg.enhancement.provider = EnhancementProvider::Groq;
        cfg.enhancement.model = Some("custom-model".into());
        assert_eq!(cfg.command.resolve(&cfg.enhancement), (EnhancementProvider::Groq, "custom-model".to_string()));
        cfg.command.provider = Some(EnhancementProvider::Anthropic);
        assert_eq!(
            cfg.command.resolve(&cfg.enhancement),
            (EnhancementProvider::Anthropic, "claude-sonnet-5".to_string())
        );
    }

    #[test]
    fn language_auto_is_none() {
        let mut t = TranscriptionSettings::default();
        assert_eq!(t.language_code(), None);
        t.language = "de".into();
        assert_eq!(t.language_code(), Some("de"));
    }

    #[test]
    fn ollama_endpoint_is_derived() {
        let e = EnhancementSettings {
            provider: EnhancementProvider::Ollama,
            ollama_base_url: "http://host:11434/".into(),
            ..Default::default()
        };
        assert_eq!(e.endpoint_for(e.provider), "http://host:11434/v1/chat/completions");
    }

    #[test]
    fn save_and_load() {
        let dir = std::env::temp_dir().join(format!("voiceink-test-{}", uuid::Uuid::new_v4()));
        let path = dir.join("config.json");
        let loaded = Config::load(&path).unwrap();
        assert!(path.exists());
        assert_eq!(loaded, Config::default());
        std::fs::remove_dir_all(dir).ok();
    }
}
