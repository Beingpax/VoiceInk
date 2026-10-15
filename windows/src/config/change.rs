//! Single-setting changes made outside the settings window (the tray menu).

use super::{Config, EnhancementProvider, HotkeyMode, PasteMethod, TranscriptionProvider};

/// A configuration change made from the tray menu.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SettingChange {
    TranscriptionProvider(TranscriptionProvider),
    Language(&'static str),
    ToggleEnhancement,
    Prompt(String),
    EnhancementProvider(EnhancementProvider),
    HotkeyMode(HotkeyMode),
    PasteMethod(PasteMethod),
    ToggleRestoreClipboard,
    ToggleFormatting,
    ToggleSounds,
    ToggleMute,
    ToggleCommandMode,
}

impl SettingChange {
    pub fn apply(&self, config: &mut Config) {
        match self {
            Self::TranscriptionProvider(p) => config.transcription.set_provider(*p),
            Self::Language(code) => config.transcription.language = (*code).to_string(),
            Self::ToggleEnhancement => config.enhancement.enabled ^= true,
            Self::Prompt(id) => config.enhancement.prompt_id.clone_from(id),
            Self::EnhancementProvider(p) => config.enhancement.set_provider(*p),
            Self::HotkeyMode(mode) => config.hotkeys.mode = *mode,
            Self::PasteMethod(method) => config.output.method = *method,
            Self::ToggleRestoreClipboard => config.output.restore_clipboard ^= true,
            Self::ToggleFormatting => config.transcription.text_formatting ^= true,
            Self::ToggleSounds => config.audio.play_sounds ^= true,
            Self::ToggleMute => config.audio.mute_system_audio ^= true,
            Self::ToggleCommandMode => config.command.enabled ^= true,
        }
    }

    /// Hotkeys must be re-installed after this change.
    pub fn affects_hotkeys(&self) -> bool {
        matches!(self, Self::HotkeyMode(_) | Self::ToggleCommandMode)
    }

    /// The provider whose API key this change starts to need, if any.
    pub fn required_key(&self, config: &Config) -> Option<&'static str> {
        match self {
            Self::TranscriptionProvider(p) => p.credential_key(),
            Self::EnhancementProvider(p) => p.credential_key(),
            Self::ToggleEnhancement if config.enhancement.enabled => config.enhancement.provider.credential_key(),
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn switching_provider_resets_the_model() {
        let mut config = Config::default();
        config.transcription.model = Some("whisper-large-v3".into());
        SettingChange::TranscriptionProvider(config.transcription.provider).apply(&mut config);
        assert!(config.transcription.model.is_some(), "same provider keeps the model");
        SettingChange::TranscriptionProvider(TranscriptionProvider::Groq).apply(&mut config);
        assert_eq!(config.transcription.provider, TranscriptionProvider::Groq);
        assert_eq!(config.transcription.model, None);
    }

    #[test]
    fn toggles_flip_and_report_side_effects() {
        let mut config = Config::default();
        let before = config.command.enabled;
        SettingChange::ToggleCommandMode.apply(&mut config);
        assert_eq!(config.command.enabled, !before);
        assert!(SettingChange::ToggleCommandMode.affects_hotkeys());
        assert!(!SettingChange::ToggleSounds.affects_hotkeys());
    }

    #[test]
    fn enabling_enhancement_requires_the_provider_key() {
        let mut config = Config::default();
        config.enhancement.enabled = false;
        SettingChange::ToggleEnhancement.apply(&mut config);
        assert_eq!(SettingChange::ToggleEnhancement.required_key(&config), Some("openai"));
        SettingChange::ToggleEnhancement.apply(&mut config);
        assert_eq!(SettingChange::ToggleEnhancement.required_key(&config), None);
        assert_eq!(SettingChange::Language("de").required_key(&config), None);
    }
}
