//! Shortcuts, microphone, overlay, sounds and autostart.

use super::super::widgets::{
    Builder, CHECK_ROW, CheckBox, ComboBox, Edit, FIELD_W, FIELD_X, HINT_GAP, Label, ROW, TOP,
};
use super::{KeyChanges, Page, PageContext, optional};
use crate::config::{Config, HotkeyMode, OverlayPosition};
use crate::input::Hotkey;
use crate::platform::{actions, capture};

const ID_EDIT_MODES: u16 = 1;

const HOTKEY_MODES: [(HotkeyMode, &str); 3] = [
    (HotkeyMode::Hybrid, "Tap to toggle, hold to talk"),
    (HotkeyMode::Toggle, "Toggle (press to start / stop)"),
    (HotkeyMode::PushToTalk, "Push to talk (hold)"),
];
const OVERLAY_POSITIONS: [(OverlayPosition, &str); 3] = [
    (OverlayPosition::BottomCenter, "Bottom center"),
    (OverlayPosition::TopCenter, "Top center"),
    (OverlayPosition::Hidden, "Hidden"),
];
const SYSTEM_DEFAULT_MIC: &str = "System default";
const THRESHOLD_RANGE_MS: (u64, u64) = (100, 5000);

pub struct General {
    record: Edit,
    mode: ComboBox,
    threshold: Edit,
    cancel: Edit,
    paste_last: Edit,
    microphone: ComboBox,
    /// Rows of `microphone` after "System default".
    microphones: Vec<String>,
    overlay: ComboBox,
    sounds: CheckBox,
    mute: CheckBox,
    autostart: CheckBox,
    modes: Label,
}

/// Parses a shortcut field; empty is allowed when `optional`.
fn shortcut(edit: Edit, name: &str, optional: bool) -> Result<String, String> {
    let spec = edit.trimmed();
    if !(optional && spec.is_empty()) {
        spec.parse::<Hotkey>().map_err(|e| format!("{name} shortcut: {e}"))?;
    }
    Ok(spec)
}

impl General {
    pub fn build(b: &mut Builder<'_>) -> Self {
        let mut y = TOP;
        b.row_label("Record shortcut", y);
        let record = b.edit(y, 200);
        y += HINT_GAP;
        b.hint("Examples: RightCtrl, F9, Ctrl+Shift+Space, Alt+Q, Mouse4", y);
        y += ROW;
        b.row_label("Shortcut behaviour", y);
        let mode = b.combo(y, 300, false, 0);
        y += ROW;
        b.row_label("Hold threshold (ms)", y);
        let threshold = b.number(y, 100);
        y += ROW;
        b.row_label("Cancel shortcut", y);
        let cancel = b.edit(y, 200);
        y += ROW;
        b.row_label("Paste last transcription", y);
        let paste_last = b.edit(y, 200);
        y += ROW + 8;
        b.row_label("Microphone", y);
        let microphone = b.combo(y, FIELD_W, false, 0);
        y += ROW;
        b.row_label("Recorder overlay", y);
        let overlay = b.combo(y, 200, false, 0);
        y += ROW + 4;
        let sounds = b.option("Play start / stop sounds", y);
        y += CHECK_ROW;
        let mute = b.option("Mute system audio while recording", y);
        y += CHECK_ROW;
        let autostart = b.option("Start VoiceInk with Windows", y);
        y += ROW + 8;
        b.row_label("Modes", y);
        let modes = b.label("", FIELD_X, y, FIELD_W - 210);
        b.button("Edit modes in config.json", FIELD_X + FIELD_W - 200, y, 200, ID_EDIT_MODES);
        Self {
            record,
            mode,
            threshold,
            cancel,
            paste_last,
            microphone,
            microphones: Vec::new(),
            overlay,
            sounds,
            mute,
            autostart,
            modes,
        }
    }

    fn show_microphones(&mut self, configured: Option<&str>) {
        self.microphones = capture::list_input_devices()
            .map(|devices| devices.into_iter().map(|(name, _)| name).collect())
            .unwrap_or_default();
        // Keep a configured device that is currently unplugged.
        if let Some(device) = configured.filter(|d| !self.microphones.iter().any(|m| m == d)) {
            self.microphones.push(device.to_string());
        }
        self.microphone.fill(std::iter::once(SYSTEM_DEFAULT_MIC).chain(self.microphones.iter().map(String::as_str)));
        let row = configured.and_then(|d| self.microphones.iter().position(|m| m == d)).map_or(0, |i| i + 1);
        self.microphone.select(row);
    }
}

impl Page for General {
    fn load(&mut self, config: &Config, _cx: &PageContext<'_>) {
        let hotkeys = &config.hotkeys;
        self.record.set(&hotkeys.record);
        self.mode.show_choices(&HOTKEY_MODES, hotkeys.mode);
        self.threshold.set(&hotkeys.hybrid_threshold_ms.to_string());
        self.cancel.set(&hotkeys.cancel);
        self.paste_last.set(hotkeys.paste_last.as_deref().unwrap_or(""));
        self.show_microphones(config.audio.input_device.as_deref().filter(|d| !d.trim().is_empty()));
        self.overlay.show_choices(&OVERLAY_POSITIONS, config.overlay);
        self.sounds.set(config.audio.play_sounds);
        self.mute.set(config.audio.mute_system_audio);
        self.autostart.set(config.start_with_windows);
        let names: Vec<&str> = config.modes.iter().map(|m| m.name.as_str()).collect();
        self.modes.set(&if names.is_empty() { "No modes configured".to_string() } else { names.join(", ") });
    }

    fn apply(&mut self, config: &mut Config, _keys: &mut KeyChanges) -> Result<(), String> {
        let hotkeys = &mut config.hotkeys;
        hotkeys.record = shortcut(self.record, "Record", false)?;
        hotkeys.mode = self.mode.choice(&HOTKEY_MODES);
        hotkeys.hybrid_threshold_ms =
            self.threshold.number("Hold threshold")?.clamp(THRESHOLD_RANGE_MS.0, THRESHOLD_RANGE_MS.1);
        hotkeys.cancel = shortcut(self.cancel, "Cancel", true)?;
        hotkeys.paste_last = optional(shortcut(self.paste_last, "Paste-last", true)?);
        config.audio.input_device =
            self.microphone.selected().filter(|&row| row > 0).and_then(|row| self.microphones.get(row - 1).cloned());
        config.overlay = self.overlay.choice(&OVERLAY_POSITIONS);
        config.audio.play_sounds = self.sounds.checked();
        config.audio.mute_system_audio = self.mute.checked();
        config.start_with_windows = self.autostart.checked();
        Ok(())
    }

    fn command(&mut self, id: u16, _code: u32, _config: &mut Config, cx: &PageContext<'_>) {
        if id == ID_EDIT_MODES {
            actions::open_config_file(cx.app);
        }
    }
}
