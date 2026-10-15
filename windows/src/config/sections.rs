//! The individual sections of [`Config`](super::Config).

use super::providers::{EnhancementProvider, TranscriptionProvider};
use crate::prompts;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum HotkeyMode {
    /// Press to start, press again to stop.
    Toggle,
    /// Hold to record, release to stop.
    PushToTalk,
    /// Short press toggles, holding longer than `hybrid_threshold_ms` acts as push-to-talk.
    #[default]
    Hybrid,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct HotkeySettings {
    /// e.g. `"RightCtrl"`, `"F9"`, `"Ctrl+Shift+Space"`, `"Alt+Q"`.
    pub record: String,
    pub mode: HotkeyMode,
    pub hybrid_threshold_ms: u64,
    /// Cancels an active recording or a running transcription.
    pub cancel: String,
    /// Optional hotkey that pastes the last transcription again.
    pub paste_last: Option<String>,
}

impl HotkeySettings {
    /// Human-readable description for menus and tooltips, e.g.
    /// `"RightCtrl (tap to toggle, hold to talk)"`.
    pub fn describe(&self) -> String {
        let mode = match self.mode {
            HotkeyMode::Toggle => "toggle",
            HotkeyMode::PushToTalk => "hold to talk",
            HotkeyMode::Hybrid => "tap to toggle, hold to talk",
        };
        format!("{} ({mode})", self.record)
    }
}

impl Default for HotkeySettings {
    fn default() -> Self {
        Self {
            record: "RightCtrl".into(),
            mode: HotkeyMode::Hybrid,
            hybrid_threshold_ms: 500,
            cancel: "Escape".into(),
            paste_last: Some("Alt+Shift+V".into()),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct TranscriptionSettings {
    pub provider: TranscriptionProvider,
    /// `None` uses the provider default.
    pub model: Option<String>,
    /// ISO-639-1 code or `"auto"`.
    pub language: String,
    /// Full URL of the `/audio/transcriptions` endpoint for the `custom` provider.
    pub custom_endpoint: String,
    /// Folder with `ggml-*.bin` models for the `local` provider
    /// (defaults to `%APPDATA%\VoiceInk\models`).
    pub local_models_dir: Option<PathBuf>,
    pub timeout_secs: u64,
    /// Remove `[MUSIC]`, `(laughs)`, tag blocks and filler words.
    pub filter_output: bool,
    /// Group sentences into paragraphs (`ParagraphFormatter`).
    pub text_formatting: bool,
}

impl Default for TranscriptionSettings {
    fn default() -> Self {
        Self {
            provider: TranscriptionProvider::OpenAI,
            model: None,
            language: "auto".into(),
            custom_endpoint: "http://127.0.0.1:8080/v1/audio/transcriptions".into(),
            local_models_dir: None,
            timeout_secs: 120,
            filter_output: true,
            text_formatting: false,
        }
    }
}

impl TranscriptionSettings {
    /// Switches provider; a model chosen for the previous provider is dropped.
    pub fn set_provider(&mut self, provider: TranscriptionProvider) {
        if provider != self.provider {
            self.provider = provider;
            self.model = None;
        }
    }

    pub fn model_name(&self) -> String {
        self.model.clone().filter(|m| !m.trim().is_empty()).unwrap_or_else(|| self.provider.default_model().to_string())
    }

    pub fn language_code(&self) -> Option<&str> {
        let lang = self.language.trim();
        (!lang.is_empty() && !lang.eq_ignore_ascii_case("auto")).then_some(lang)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct EnhancementSettings {
    pub enabled: bool,
    pub provider: EnhancementProvider,
    pub model: Option<String>,
    pub prompt_id: String,
    /// Base URL for Ollama (`/v1/chat/completions` is appended).
    pub ollama_base_url: String,
    /// Full chat-completions URL for the `custom` provider.
    pub custom_endpoint: String,
    pub use_clipboard_context: bool,
    /// Sends the focused window's title and process name as context.
    pub use_window_context: bool,
    /// Copies the current selection (Ctrl+C) before recording and sends it as context.
    pub use_selected_text_context: bool,
    pub timeout_secs: u64,
    pub max_attempts: u32,
    pub retry_on_timeout: bool,
    pub skip_short_transcripts: bool,
    pub short_transcript_word_threshold: usize,
}

impl Default for EnhancementSettings {
    fn default() -> Self {
        Self {
            enabled: false,
            provider: EnhancementProvider::OpenAI,
            model: None,
            prompt_id: prompts::DEFAULT_PROMPT_ID.into(),
            ollama_base_url: "http://localhost:11434".into(),
            custom_endpoint: "http://127.0.0.1:1234/v1/chat/completions".into(),
            use_clipboard_context: false,
            use_window_context: true,
            use_selected_text_context: false,
            timeout_secs: 30,
            max_attempts: 3,
            retry_on_timeout: true,
            skip_short_transcripts: false,
            short_transcript_word_threshold: 3,
        }
    }
}

impl EnhancementSettings {
    /// Switches provider; a model chosen for the previous provider is dropped.
    pub fn set_provider(&mut self, provider: EnhancementProvider) {
        if provider != self.provider {
            self.provider = provider;
            self.model = None;
        }
    }

    pub fn model_name(&self) -> String {
        self.model.clone().filter(|m| !m.trim().is_empty()).unwrap_or_else(|| self.provider.default_model().to_string())
    }

    /// Chat endpoint for `provider` (modes and Command Mode may use a
    /// different provider than the global one).
    pub fn endpoint_for(&self, provider: EnhancementProvider) -> String {
        match provider {
            EnhancementProvider::Ollama => {
                format!("{}/v1/chat/completions", self.ollama_base_url.trim_end_matches('/'))
            }
            EnhancementProvider::Custom => self.custom_endpoint.trim().to_string(),
            p => p.endpoint().unwrap_or_default().to_string(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum PasteMethod {
    /// Clipboard + Ctrl+V (default, like the macOS `CGEvent` paste).
    #[default]
    CtrlV,
    /// Clipboard + Shift+Insert (terminals, some legacy apps).
    ShiftInsert,
    /// Types the text with Unicode `SendInput` events, leaving the clipboard alone.
    Type,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum SendKey {
    #[default]
    None,
    Enter,
    ShiftEnter,
    CtrlEnter,
}

/// Command Mode: select text, hold the command shortcut and say what to do
/// with it ("make this more formal", "translate to German"). Without a
/// selection the instruction writes new text at the cursor.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct CommandSettings {
    pub enabled: bool,
    /// Uses the same behaviour (hybrid / toggle / push-to-talk) as the record shortcut.
    pub hotkey: String,
    /// `None` uses the AI Enhancement provider and model.
    pub provider: Option<EnhancementProvider>,
    pub model: Option<String>,
}

impl Default for CommandSettings {
    fn default() -> Self {
        Self { enabled: true, hotkey: "Ctrl+Shift+Space".into(), provider: None, model: None }
    }
}

impl CommandSettings {
    /// Effective provider and model, falling back to the enhancement settings.
    pub fn resolve(&self, enhancement: &EnhancementSettings) -> (EnhancementProvider, String) {
        let provider = self.provider.unwrap_or(enhancement.provider);
        let model = self.model.clone().filter(|m| !m.trim().is_empty()).unwrap_or_else(|| {
            if self.provider.is_none() { enhancement.model_name() } else { provider.default_model().to_string() }
        });
        (provider, model)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct OutputSettings {
    pub method: PasteMethod,
    pub restore_clipboard: bool,
    pub clipboard_restore_delay_ms: u64,
    /// Key pressed after pasting ("Finish & Send").
    pub send_key: SendKey,
    /// Appends a trailing space so consecutive dictations don't run together.
    pub append_space: bool,
}

impl Default for OutputSettings {
    fn default() -> Self {
        Self {
            method: PasteMethod::CtrlV,
            restore_clipboard: true,
            clipboard_restore_delay_ms: 600,
            send_key: SendKey::None,
            append_space: false,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct AudioSettings {
    /// Substring of the microphone's friendly name; `None` = system default.
    pub input_device: Option<String>,
    pub play_sounds: bool,
    /// Custom WAV files; built-in sounds are used when unset.
    pub start_sound: Option<PathBuf>,
    pub stop_sound: Option<PathBuf>,
    /// Mutes system output while recording (restored afterwards).
    pub mute_system_audio: bool,
    /// Recordings shorter than this are discarded.
    pub min_recording_ms: u64,
}

impl Default for AudioSettings {
    fn default() -> Self {
        Self {
            input_device: None,
            play_sounds: true,
            start_sound: None,
            stop_sound: None,
            mute_system_audio: false,
            min_recording_ms: 300,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct HistorySettings {
    pub enabled: bool,
    pub save_audio: bool,
    /// Oldest entries beyond this count are dropped (0 = unlimited).
    pub max_entries: usize,
}

impl Default for HistorySettings {
    fn default() -> Self {
        Self { enabled: true, save_audio: false, max_entries: 1000 }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum OverlayPosition {
    #[default]
    BottomCenter,
    TopCenter,
    Hidden,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum OutputMode {
    #[default]
    Paste,
    /// Runs `custom_command` with the text on stdin and in `VOICEINK_TRANSCRIPT`.
    CustomCommand,
}

/// Per-application overrides (the macOS "Modes"/Power Mode feature).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct ModeConfig {
    pub name: String,
    pub enabled: bool,
    /// Executable names, e.g. `["slack.exe", "teams.exe"]` (case-insensitive).
    pub process_names: Vec<String>,
    /// Matched against the focused window title, e.g. browser tabs: `["Gmail", "github.com"]`.
    pub window_title_contains: Vec<String>,
    /// Spoken at the beginning of a dictation to force this mode ("email ...").
    pub trigger_words: Vec<String>,
    pub enhancement_enabled: Option<bool>,
    pub prompt_id: Option<String>,
    pub enhancement_provider: Option<EnhancementProvider>,
    pub enhancement_model: Option<String>,
    pub language: Option<String>,
    pub text_formatting: Option<bool>,
    pub use_clipboard_context: Option<bool>,
    pub use_selected_text_context: Option<bool>,
    pub output: OutputMode,
    pub custom_command: Option<String>,
    pub send_key: Option<SendKey>,
}

impl Default for ModeConfig {
    fn default() -> Self {
        Self {
            name: String::new(),
            enabled: true,
            process_names: Vec::new(),
            window_title_contains: Vec::new(),
            trigger_words: Vec::new(),
            enhancement_enabled: None,
            prompt_id: None,
            enhancement_provider: None,
            enhancement_model: None,
            language: None,
            text_formatting: None,
            use_clipboard_context: None,
            use_selected_text_context: None,
            output: OutputMode::Paste,
            custom_command: None,
            send_key: None,
        }
    }
}
