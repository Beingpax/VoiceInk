//! User configuration, persisted as pretty JSON in `%APPDATA%\VoiceInk\config.json`.
//!
//! This replaces the `UserDefaults` keys scattered through the macOS app with a
//! single typed document that users can also edit by hand ("Open settings
//! file" in the tray menu). Every field has a default so older files keep
//! loading after new options are added.

use crate::prompts::{self, CustomPrompt};
use crate::text::{Snippet, WordReplacement, DEFAULT_FILLER_WORDS};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TranscriptionProvider {
    Groq,
    #[serde(rename = "openai")]
    OpenAI,
    Deepgram,
    #[serde(rename = "elevenlabs")]
    ElevenLabs,
    Mistral,
    /// Any OpenAI-compatible `/audio/transcriptions` endpoint (e.g. a local
    /// `whisper.cpp` server, LocalAI, faster-whisper-server).
    Custom,
    /// Offline whisper.cpp (requires the `local-whisper` build feature).
    Local,
}

impl TranscriptionProvider {
    pub const ALL: [TranscriptionProvider; 7] = [
        Self::OpenAI,
        Self::Groq,
        Self::Deepgram,
        Self::ElevenLabs,
        Self::Mistral,
        Self::Custom,
        Self::Local,
    ];

    pub fn display_name(self) -> &'static str {
        match self {
            Self::Groq => "Groq",
            Self::OpenAI => "OpenAI",
            Self::Deepgram => "Deepgram",
            Self::ElevenLabs => "ElevenLabs",
            Self::Mistral => "Mistral",
            Self::Custom => "Custom (OpenAI-compatible)",
            Self::Local => "Local (whisper.cpp)",
        }
    }

    /// Name under which the API key is stored (shared with enhancement providers).
    pub fn key_name(self) -> &'static str {
        match self {
            Self::Groq => "groq",
            Self::OpenAI => "openai",
            Self::Deepgram => "deepgram",
            Self::ElevenLabs => "elevenlabs",
            Self::Mistral => "mistral",
            Self::Custom => "custom-transcription",
            Self::Local => "",
        }
    }

    pub fn default_model(self) -> &'static str {
        match self {
            Self::Groq => "whisper-large-v3-turbo",
            Self::OpenAI => "gpt-4o-transcribe",
            Self::Deepgram => "nova-3",
            Self::ElevenLabs => "scribe_v2",
            Self::Mistral => "voxtral-mini-latest",
            Self::Custom => "whisper-1",
            Self::Local => "ggml-base.en.bin",
        }
    }

    pub fn models(self) -> &'static [&'static str] {
        match self {
            Self::Groq => &["whisper-large-v3-turbo", "whisper-large-v3"],
            Self::OpenAI => &["gpt-4o-transcribe", "gpt-4o-mini-transcribe", "whisper-1"],
            Self::Deepgram => &["nova-3", "nova-3-medical"],
            Self::ElevenLabs => &["scribe_v2", "scribe_v2_medical"],
            Self::Mistral => &["voxtral-mini-latest"],
            Self::Custom | Self::Local => &[],
        }
    }

    pub fn requires_api_key(self) -> bool {
        !matches!(self, Self::Local | Self::Custom)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum EnhancementProvider {
    #[serde(rename = "openai")]
    OpenAI,
    Anthropic,
    Gemini,
    Groq,
    Cerebras,
    Mistral,
    #[serde(rename = "openrouter")]
    OpenRouter,
    Ollama,
    /// Any OpenAI-compatible `/chat/completions` endpoint (LM Studio, vLLM, ...).
    Custom,
}

impl EnhancementProvider {
    pub const ALL: [EnhancementProvider; 9] = [
        Self::OpenAI,
        Self::Anthropic,
        Self::Gemini,
        Self::Groq,
        Self::Cerebras,
        Self::Mistral,
        Self::OpenRouter,
        Self::Ollama,
        Self::Custom,
    ];

    pub fn display_name(self) -> &'static str {
        match self {
            Self::OpenAI => "OpenAI",
            Self::Anthropic => "Anthropic",
            Self::Gemini => "Gemini",
            Self::Groq => "Groq",
            Self::Cerebras => "Cerebras",
            Self::Mistral => "Mistral",
            Self::OpenRouter => "OpenRouter",
            Self::Ollama => "Ollama",
            Self::Custom => "Custom (OpenAI-compatible)",
        }
    }

    pub fn key_name(self) -> &'static str {
        match self {
            Self::OpenAI => "openai",
            Self::Anthropic => "anthropic",
            Self::Gemini => "gemini",
            Self::Groq => "groq",
            Self::Cerebras => "cerebras",
            Self::Mistral => "mistral",
            Self::OpenRouter => "openrouter",
            Self::Ollama => "",
            Self::Custom => "custom-enhancement",
        }
    }

    /// Chat endpoint; `None` for providers whose URL comes from the config.
    pub fn endpoint(self) -> Option<&'static str> {
        match self {
            Self::OpenAI => Some("https://api.openai.com/v1/chat/completions"),
            Self::Anthropic => Some("https://api.anthropic.com/v1/messages"),
            Self::Gemini => {
                Some("https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
            }
            Self::Groq => Some("https://api.groq.com/openai/v1/chat/completions"),
            Self::Cerebras => Some("https://api.cerebras.ai/v1/chat/completions"),
            Self::Mistral => Some("https://api.mistral.ai/v1/chat/completions"),
            Self::OpenRouter => Some("https://openrouter.ai/api/v1/chat/completions"),
            Self::Ollama | Self::Custom => None,
        }
    }

    /// Defaults match `AIProvider.defaultModel` in the macOS app.
    pub fn default_model(self) -> &'static str {
        match self {
            Self::Cerebras => "qwen-3.8-27b",
            Self::Groq => "qwen/qwen3.8-27b",
            Self::Gemini => "gemini-3.8-flash",
            Self::Anthropic => "claude-sonnet-5",
            Self::OpenAI => "gpt-6-luna",
            Self::Mistral => "mistral-small-latest",
            Self::OpenRouter => "qwen/qwen3.8-27b",
            Self::Ollama => "mistral",
            Self::Custom => "",
        }
    }

    pub fn models(self) -> &'static [&'static str] {
        match self {
            Self::Cerebras => &["qwen-3.8-27b", "gpt-oss-120b"],
            Self::Groq => &[
                "qwen/qwen3.8-27b",
                "openai/gpt-oss-120b",
                "openai/gpt-oss-20b",
            ],
            Self::Gemini => &[
                "gemini-3.8-flash",
                "gemini-3.7-flash",
                "gemini-3.5-flash",
                "gemini-3.5-flash-lite",
                "gemini-3.1-pro-preview",
            ],
            Self::Anthropic => &["claude-sonnet-5", "claude-haiku-4-5"],
            Self::OpenAI => &[
                "gpt-6-luna",
                "gpt-6-sol",
                "gpt-5.6-luna",
                "gpt-5.5",
                "gpt-5.4-mini",
                "gpt-4.1-mini",
            ],
            Self::Mistral => &[
                "mistral-small-latest",
                "mistral-medium-latest",
                "mistral-large-latest",
            ],
            Self::OpenRouter | Self::Ollama | Self::Custom => &[],
        }
    }

    pub fn requires_api_key(self) -> bool {
        !matches!(self, Self::Ollama | Self::Custom)
    }

    /// OpenRouter and local servers are not rate limited client-side (as on macOS).
    pub fn is_rate_limited(self) -> bool {
        !matches!(self, Self::OpenRouter | Self::Ollama)
    }
}

/// Languages offered in the menu and dashboard (`auto` = provider auto-detect).
pub const LANGUAGES: &[(&str, &str)] = &[
    ("auto", "Auto-detect"),
    ("en", "English"),
    ("de", "German"),
    ("fr", "French"),
    ("es", "Spanish"),
    ("it", "Italian"),
    ("pt", "Portuguese"),
    ("nl", "Dutch"),
    ("pl", "Polish"),
    ("ru", "Russian"),
    ("uk", "Ukrainian"),
    ("tr", "Turkish"),
    ("ja", "Japanese"),
    ("zh", "Chinese"),
    ("ko", "Korean"),
    ("hi", "Hindi"),
    ("ar", "Arabic"),
];

// ---------------------------------------------------------------------------
// Settings sections
// ---------------------------------------------------------------------------

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
    pub fn model_name(&self) -> String {
        self.model
            .clone()
            .filter(|m| !m.trim().is_empty())
            .unwrap_or_else(|| self.provider.default_model().to_string())
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
    pub fn model_name(&self) -> String {
        self.model
            .clone()
            .filter(|m| !m.trim().is_empty())
            .unwrap_or_else(|| self.provider.default_model().to_string())
    }

    pub fn endpoint(&self) -> String {
        match self.provider {
            EnhancementProvider::Ollama => format!(
                "{}/v1/chat/completions",
                self.ollama_base_url.trim_end_matches('/')
            ),
            EnhancementProvider::Custom => self.custom_endpoint.clone(),
            p => p.endpoint().unwrap_or_default().to_string(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum PasteMethod {
    /// Clipboard + Ctrl+V (default, like the macOS CGEvent paste).
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
        Self {
            enabled: true,
            hotkey: "Ctrl+Shift+Space".into(),
            provider: None,
            model: None,
        }
    }
}

impl CommandSettings {
    /// Effective provider and model, falling back to the enhancement settings.
    pub fn resolve(&self, enhancement: &EnhancementSettings) -> (EnhancementProvider, String) {
        let provider = self.provider.unwrap_or(enhancement.provider);
        let model = self
            .model
            .clone()
            .filter(|m| !m.trim().is_empty())
            .unwrap_or_else(|| {
                if self.provider.is_none() {
                    enhancement.model_name()
                } else {
                    provider.default_model().to_string()
                }
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
        Self {
            enabled: true,
            save_audio: false,
            max_entries: 1000,
        }
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

// ---------------------------------------------------------------------------
// Root
// ---------------------------------------------------------------------------

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
            filler_words: DEFAULT_FILLER_WORDS.iter().map(|s| s.to_string()).collect(),
            vocabulary: Vec::new(),
            replacements: Vec::new(),
            snippets: Vec::new(),
            modes: Vec::new(),
        }
    }
}

impl Config {
    pub fn prompt(&self, id: &str) -> Option<&CustomPrompt> {
        self.prompts.iter().find(|p| p.id == id)
    }

    /// Selected prompt, falling back to the first prompt (like `repairModePromptSelections`).
    pub fn active_prompt(&self, id: Option<&str>) -> Option<&CustomPrompt> {
        id.and_then(|id| self.prompt(id))
            .or_else(|| self.prompt(&self.enhancement.prompt_id))
            .or_else(|| self.prompts.first())
    }

    pub fn load(path: &Path) -> Result<Self, String> {
        match std::fs::read_to_string(path) {
            Ok(text) => {
                let mut cfg: Config =
                    serde_json::from_str(&text).map_err(|e| format!("{}: {e}", path.display()))?;
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
            Err(e) => Err(format!("{}: {e}", path.display())),
        }
    }

    pub fn save(&self, path: &Path) -> Result<(), String> {
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
        }
        let json = serde_json::to_string_pretty(self).map_err(|e| e.to_string())?;
        // Write-then-rename so a crash never leaves a truncated config behind.
        let tmp = path.with_extension("json.tmp");
        std::fs::write(&tmp, json).map_err(|e| e.to_string())?;
        std::fs::rename(&tmp, path).map_err(|e| e.to_string())
    }
}

/// `%APPDATA%\VoiceInk` (or `$XDG_CONFIG_HOME/VoiceInk` when testing elsewhere).
pub fn data_dir() -> PathBuf {
    if let Ok(dir) = std::env::var("VOICEINK_HOME") {
        return PathBuf::from(dir);
    }
    let base = std::env::var_os("APPDATA")
        .or_else(|| std::env::var_os("XDG_CONFIG_HOME"))
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))
        .unwrap_or_else(|| PathBuf::from("."));
    base.join(crate::APP_NAME)
}

pub fn config_path() -> PathBuf {
    data_dir().join("config.json")
}

// ---------------------------------------------------------------------------
// Hotkey parsing
// ---------------------------------------------------------------------------

/// Virtual-key codes used by the parser (values from `WinUser.h`).
pub mod vk {
    pub const BACK: u16 = 0x08;
    pub const TAB: u16 = 0x09;
    pub const RETURN: u16 = 0x0D;
    pub const SHIFT: u16 = 0x10;
    pub const CONTROL: u16 = 0x11;
    pub const MENU: u16 = 0x12;
    pub const PAUSE: u16 = 0x13;
    pub const CAPITAL: u16 = 0x14;
    pub const ESCAPE: u16 = 0x1B;
    pub const SPACE: u16 = 0x20;
    pub const PRIOR: u16 = 0x21;
    pub const NEXT: u16 = 0x22;
    pub const END: u16 = 0x23;
    pub const HOME: u16 = 0x24;
    pub const LEFT: u16 = 0x25;
    pub const UP: u16 = 0x26;
    pub const RIGHT: u16 = 0x27;
    pub const DOWN: u16 = 0x28;
    pub const SNAPSHOT: u16 = 0x2C;
    pub const INSERT: u16 = 0x2D;
    pub const DELETE: u16 = 0x2E;
    pub const LWIN: u16 = 0x5B;
    pub const RWIN: u16 = 0x5C;
    pub const APPS: u16 = 0x5D;
    pub const F1: u16 = 0x70;
    pub const SCROLL: u16 = 0x91;
    pub const LSHIFT: u16 = 0xA0;
    pub const RSHIFT: u16 = 0xA1;
    pub const LCONTROL: u16 = 0xA2;
    pub const RCONTROL: u16 = 0xA3;
    pub const LMENU: u16 = 0xA4;
    pub const RMENU: u16 = 0xA5;
    pub const XBUTTON1: u16 = 0x05;
    pub const XBUTTON2: u16 = 0x06;
    pub const MBUTTON: u16 = 0x04;
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Modifiers {
    pub ctrl: bool,
    pub alt: bool,
    pub shift: bool,
    pub win: bool,
}

impl Modifiers {
    pub fn is_empty(&self) -> bool {
        !(self.ctrl || self.alt || self.shift || self.win)
    }
}

/// A parsed hotkey.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Hotkey {
    /// A modifier pressed and released on its own, e.g. `RightCtrl`.
    ModifierOnly { vk: u16 },
    /// A regular key with optional modifiers, e.g. `Ctrl+Shift+Space` or `F9`.
    Key { vk: u16, modifiers: Modifiers },
    /// A mouse button (`Mouse4`, `Mouse5`, `MiddleMouse`).
    Mouse { button: u16 },
}

pub fn is_modifier_vk(code: u16) -> bool {
    matches!(
        code,
        vk::SHIFT
            | vk::CONTROL
            | vk::MENU
            | vk::LSHIFT
            | vk::RSHIFT
            | vk::LCONTROL
            | vk::RCONTROL
            | vk::LMENU
            | vk::RMENU
            | vk::LWIN
            | vk::RWIN
    )
}

fn key_name_to_vk(name: &str) -> Option<u16> {
    let n = name
        .trim()
        .to_ascii_lowercase()
        .replace([' ', '_', '-'], "");
    let code = match n.as_str() {
        "rightctrl" | "rctrl" | "rightcontrol" => vk::RCONTROL,
        "leftctrl" | "lctrl" | "leftcontrol" => vk::LCONTROL,
        "rightalt" | "ralt" | "altgr" => vk::RMENU,
        "leftalt" | "lalt" => vk::LMENU,
        "rightshift" | "rshift" => vk::RSHIFT,
        "leftshift" | "lshift" => vk::LSHIFT,
        "rightwin" | "rwin" => vk::RWIN,
        "leftwin" | "lwin" => vk::LWIN,
        "space" => vk::SPACE,
        "enter" | "return" => vk::RETURN,
        "tab" => vk::TAB,
        "esc" | "escape" => vk::ESCAPE,
        "backspace" => vk::BACK,
        "pause" | "break" => vk::PAUSE,
        "capslock" => vk::CAPITAL,
        "scrolllock" => vk::SCROLL,
        "printscreen" | "prtsc" => vk::SNAPSHOT,
        "insert" | "ins" => vk::INSERT,
        "delete" | "del" => vk::DELETE,
        "home" => vk::HOME,
        "end" => vk::END,
        "pageup" | "pgup" => vk::PRIOR,
        "pagedown" | "pgdn" => vk::NEXT,
        "left" => vk::LEFT,
        "right" => vk::RIGHT,
        "up" => vk::UP,
        "down" => vk::DOWN,
        "menu" | "apps" => vk::APPS,
        "`" | "backtick" | "grave" => 0xC0,
        "," | "comma" => 0xBC,
        "." | "period" => 0xBE,
        "/" | "slash" => 0xBF,
        ";" | "semicolon" => 0xBA,
        _ => {
            if let Some(num) = n.strip_prefix('f').and_then(|d| d.parse::<u16>().ok()) {
                if (1..=24).contains(&num) {
                    return Some(vk::F1 + num - 1);
                }
                return None;
            }
            let mut chars = n.chars();
            match (chars.next(), chars.next()) {
                (Some(c), None) if c.is_ascii_alphanumeric() => c.to_ascii_uppercase() as u16,
                _ => return None,
            }
        }
    };
    Some(code)
}

fn mouse_name(name: &str) -> Option<u16> {
    match name
        .trim()
        .to_ascii_lowercase()
        .replace([' ', '_', '-'], "")
        .as_str()
    {
        "mouse4" | "xbutton1" | "mouseback" => Some(vk::XBUTTON1),
        "mouse5" | "xbutton2" | "mouseforward" => Some(vk::XBUTTON2),
        "middlemouse" | "mouse3" | "mbutton" => Some(vk::MBUTTON),
        _ => None,
    }
}

pub fn parse_hotkey(spec: &str) -> Result<Hotkey, String> {
    let parts: Vec<&str> = spec
        .split('+')
        .map(str::trim)
        .filter(|p| !p.is_empty())
        .collect();
    if parts.is_empty() {
        return Err("empty hotkey".into());
    }
    if parts.len() == 1 {
        if let Some(button) = mouse_name(parts[0]) {
            return Ok(Hotkey::Mouse { button });
        }
        let code = key_name_to_vk(parts[0]).ok_or_else(|| format!("unknown key '{}'", parts[0]))?;
        return Ok(if is_modifier_vk(code) {
            Hotkey::ModifierOnly { vk: code }
        } else {
            Hotkey::Key {
                vk: code,
                modifiers: Modifiers::default(),
            }
        });
    }

    let mut modifiers = Modifiers::default();
    for part in &parts[..parts.len() - 1] {
        match part.to_ascii_lowercase().as_str() {
            "ctrl" | "control" => modifiers.ctrl = true,
            "alt" => modifiers.alt = true,
            "shift" => modifiers.shift = true,
            "win" | "super" | "meta" => modifiers.win = true,
            other => return Err(format!("unknown modifier '{other}'")),
        }
    }
    let last = parts[parts.len() - 1];
    let code = key_name_to_vk(last).ok_or_else(|| format!("unknown key '{last}'"))?;
    if is_modifier_vk(code) {
        return Err("the last part of a key combination must be a non-modifier key".into());
    }
    Ok(Hotkey::Key {
        vk: code,
        modifiers,
    })
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
        let cfg: Config = serde_json::from_str(
            r#"{"transcription": {"provider": "deepgram"}, "enhancement": {"enabled": true}}"#,
        )
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
        assert_eq!(
            TranscriptionProvider::OpenAI.key_name(),
            EnhancementProvider::OpenAI.key_name()
        );
    }

    #[test]
    fn command_falls_back_to_enhancement_model() {
        let mut cfg = Config::default();
        cfg.enhancement.provider = EnhancementProvider::Groq;
        cfg.enhancement.model = Some("custom-model".into());
        assert_eq!(
            cfg.command.resolve(&cfg.enhancement),
            (EnhancementProvider::Groq, "custom-model".to_string())
        );
        cfg.command.provider = Some(EnhancementProvider::Anthropic);
        assert_eq!(
            cfg.command.resolve(&cfg.enhancement),
            (
                EnhancementProvider::Anthropic,
                "claude-sonnet-5".to_string()
            )
        );
        assert!(parse_hotkey(&CommandSettings::default().hotkey).is_ok());
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
        assert_eq!(e.endpoint(), "http://host:11434/v1/chat/completions");
    }

    #[test]
    fn parses_hotkeys() {
        assert_eq!(
            parse_hotkey("RightCtrl").unwrap(),
            Hotkey::ModifierOnly { vk: vk::RCONTROL }
        );
        assert_eq!(
            parse_hotkey("F9").unwrap(),
            Hotkey::Key {
                vk: 0x78,
                modifiers: Modifiers::default()
            }
        );
        assert_eq!(
            parse_hotkey("Ctrl+Shift+Space").unwrap(),
            Hotkey::Key {
                vk: vk::SPACE,
                modifiers: Modifiers {
                    ctrl: true,
                    shift: true,
                    ..Default::default()
                }
            }
        );
        assert_eq!(
            parse_hotkey("alt+q").unwrap(),
            Hotkey::Key {
                vk: b'Q' as u16,
                modifiers: Modifiers {
                    alt: true,
                    ..Default::default()
                }
            }
        );
        assert_eq!(
            parse_hotkey("Mouse4").unwrap(),
            Hotkey::Mouse {
                button: vk::XBUTTON1
            }
        );
        assert!(parse_hotkey("Ctrl+Shift").is_err());
        assert!(parse_hotkey("Hyper+K").is_err());
        assert!(parse_hotkey("F25").is_err());
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
