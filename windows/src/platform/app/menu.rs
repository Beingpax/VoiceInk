//! The tray menu: what it shows ([`build`]) and what each item does
//! ([`MenuAction`]). Item ids are assigned by [`Items`], so there are no
//! hand-maintained id ranges.

use super::super::tray::Menu;
use crate::APP_VERSION;
use crate::config::{
    Config, EnhancementProvider, HotkeyMode, LANGUAGES, PasteMethod, SettingChange, TranscriptionProvider,
};
use crate::credentials::SecretStore;
use crate::settings_page::SettingsPage;

/// Prompts beyond this count are only reachable in the settings window.
const MAX_MENU_PROMPTS: usize = 40;

const HOTKEY_MODES: [(HotkeyMode, &str); 3] = [
    (HotkeyMode::Hybrid, "Tap to toggle, hold to talk"),
    (HotkeyMode::Toggle, "Toggle"),
    (HotkeyMode::PushToTalk, "Push to talk"),
];
const PASTE_METHODS: [(PasteMethod, &str); 3] = [
    (PasteMethod::CtrlV, "Ctrl+V"),
    (PasteMethod::ShiftInsert, "Shift+Insert"),
    (PasteMethod::Type, "Simulated typing"),
];

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MenuAction {
    /// Start, stop or cancel depending on the current state.
    ToggleRecording,
    PasteLast,
    OpenSettings(SettingsPage),
    Setting(SettingChange),
    ToggleAutostart,
    OpenConfigFile,
    ReloadConfig,
    OpenHistoryCsv,
    OpenDataFolder,
    About,
    Quit,
}

/// Assigns menu ids and remembers the action behind each.
#[derive(Default)]
pub struct Items {
    actions: Vec<MenuAction>,
}

impl Items {
    fn add(&mut self, action: MenuAction) -> usize {
        self.actions.push(action);
        self.actions.len() // ids start at 1; 0 means "nothing chosen"
    }

    fn item(&mut self, menu: &Menu, text: &str, action: MenuAction) {
        menu.item(self.add(action), text);
    }

    fn check(&mut self, menu: &Menu, text: &str, checked: bool, action: MenuAction) {
        menu.check(self.add(action), text, checked);
    }

    fn setting(&mut self, menu: &Menu, text: &str, checked: bool, change: SettingChange) {
        self.check(menu, text, checked, MenuAction::Setting(change));
    }

    /// The action for an id returned by [`Menu::track`].
    pub fn take(mut self, id: usize) -> Option<MenuAction> {
        id.checked_sub(1).filter(|&i| i < self.actions.len()).map(|i| self.actions.swap_remove(i))
    }
}

/// What the menu needs to know about the app.
pub struct MenuState<'a> {
    pub config: &'a Config,
    pub secrets: &'a dyn SecretStore,
    /// Label of the start/stop item ("Start recording", ...).
    pub toggle_label: &'static str,
    pub autostart: bool,
}

impl MenuState<'_> {
    fn key_suffix(&self, credential: Option<&str>) -> &'static str {
        if credential.is_some_and(|name| !self.secrets.has(name)) { "  (no key)" } else { "" }
    }
}

pub fn build(state: &MenuState<'_>) -> (Menu, Items) {
    let config = state.config;
    let mut items = Items::default();
    let menu = Menu::new();
    menu.disabled(&format!("VoiceInk {APP_VERSION}"));
    menu.disabled(&format!("Shortcut: {}", config.hotkeys.describe()));
    if config.command.enabled {
        menu.disabled(&format!("Command Mode: {}", config.command.hotkey));
    }
    menu.separator();
    items.item(&menu, "Dashboard…", MenuAction::OpenSettings(SettingsPage::Dashboard));
    items.item(&menu, "Settings…", MenuAction::OpenSettings(SettingsPage::General));
    menu.separator();
    items.item(&menu, state.toggle_label, MenuAction::ToggleRecording);
    items.item(&menu, "Paste last transcription", MenuAction::PasteLast);
    menu.separator();
    menu.submenu(
        &format!("Transcription: {}", config.transcription.provider.display_name()),
        transcription_menu(state, &mut items),
    );
    menu.submenu("Language", language_menu(config, &mut items));
    let enhancement_state = if config.enhancement.enabled { "On" } else { "Off" };
    menu.submenu(&format!("AI Enhancement: {enhancement_state}"), enhancement_menu(state, &mut items));
    items.item(&menu, "API keys…", MenuAction::OpenSettings(SettingsPage::Transcription));
    menu.submenu("Options", options_menu(config, &mut items));
    menu.separator();
    items.check(&menu, "Start with Windows", state.autostart, MenuAction::ToggleAutostart);
    items.item(&menu, "Open settings file", MenuAction::OpenConfigFile);
    items.item(&menu, "Reload settings", MenuAction::ReloadConfig);
    items.item(&menu, "Open history (CSV)", MenuAction::OpenHistoryCsv);
    items.item(&menu, "Open data folder", MenuAction::OpenDataFolder);
    menu.separator();
    items.item(&menu, "About VoiceInk", MenuAction::About);
    items.item(&menu, "Quit", MenuAction::Quit);
    (menu, items)
}

fn transcription_menu(state: &MenuState<'_>, items: &mut Items) -> Menu {
    let menu = Menu::new();
    for provider in TranscriptionProvider::ALL {
        let text = format!("{}{}", provider.display_name(), state.key_suffix(provider.credential_key()));
        let checked = state.config.transcription.provider == provider;
        items.setting(&menu, &text, checked, SettingChange::TranscriptionProvider(provider));
    }
    menu
}

fn language_menu(config: &Config, items: &mut Items) -> Menu {
    let menu = Menu::new();
    for (code, name) in LANGUAGES {
        let checked = config.transcription.language.eq_ignore_ascii_case(code);
        items.setting(&menu, name, checked, SettingChange::Language(code));
    }
    menu
}

fn enhancement_menu(state: &MenuState<'_>, items: &mut Items) -> Menu {
    let settings = &state.config.enhancement;
    let menu = Menu::new();
    items.setting(&menu, "Enabled", settings.enabled, SettingChange::ToggleEnhancement);
    menu.separator();
    menu.disabled("Prompt");
    for prompt in state.config.prompts.iter().take(MAX_MENU_PROMPTS) {
        let checked = settings.prompt_id == prompt.id;
        items.setting(&menu, &prompt.title, checked, SettingChange::Prompt(prompt.id.clone()));
    }
    menu.separator();
    menu.disabled("Provider");
    for provider in EnhancementProvider::ALL {
        let text = format!("{}{}", provider.display_name(), state.key_suffix(provider.credential_key()));
        items.setting(&menu, &text, settings.provider == provider, SettingChange::EnhancementProvider(provider));
    }
    menu
}

fn options_menu(config: &Config, items: &mut Items) -> Menu {
    let menu = Menu::new();
    menu.disabled("Shortcut behaviour");
    for (mode, label) in HOTKEY_MODES {
        items.setting(&menu, label, config.hotkeys.mode == mode, SettingChange::HotkeyMode(mode));
    }
    menu.separator();
    menu.disabled("Insert text with");
    for (method, label) in PASTE_METHODS {
        items.setting(&menu, label, config.output.method == method, SettingChange::PasteMethod(method));
    }
    menu.separator();
    let toggles = [
        (
            "Restore clipboard after paste".to_string(),
            config.output.restore_clipboard,
            SettingChange::ToggleRestoreClipboard,
        ),
        ("Paragraph formatting".to_string(), config.transcription.text_formatting, SettingChange::ToggleFormatting),
        ("Sound feedback".to_string(), config.audio.play_sounds, SettingChange::ToggleSounds),
        ("Mute system audio while recording".to_string(), config.audio.mute_system_audio, SettingChange::ToggleMute),
        (format!("Command Mode ({})", config.command.hotkey), config.command.enabled, SettingChange::ToggleCommandMode),
    ];
    for (label, checked, change) in toggles {
        items.setting(&menu, &label, checked, change);
    }
    menu
}
