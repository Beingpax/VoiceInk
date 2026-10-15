//! Press/release state machine for recording shortcuts.
//!
//! The Win32 keyboard hook feeds raw key events into [`Trigger`]s, which turn
//! them into [`HotkeyEvent`]s according to the configured [`HotkeyMode`]. The
//! logic is platform independent so it can be unit tested.

use super::hotkey::{Hotkey, Modifiers, is_modifier_vk, vk};
use crate::config::HotkeyMode;

/// Which recording a shortcut starts.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TriggerKind {
    /// Normal dictation.
    Dictation,
    /// Command Mode: the speech is an instruction for the selected text.
    Command,
}

/// High-level shortcut events delivered to the application.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HotkeyEvent {
    /// A record shortcut was pressed (or, for toggle-on-release, tapped).
    Down(TriggerKind),
    Up(TriggerKind),
    /// A modifier-only shortcut turned out to be part of another shortcut.
    Abort(TriggerKind),
    Cancel,
    PasteLast,
}

impl HotkeyEvent {
    const COMMAND_OFFSET: usize = 10;

    /// Encodes the event for a window message parameter.
    pub fn to_wparam(self) -> usize {
        let offset = |k: TriggerKind| match k {
            TriggerKind::Dictation => 0,
            TriggerKind::Command => Self::COMMAND_OFFSET,
        };
        match self {
            Self::Down(k) => 1 + offset(k),
            Self::Up(k) => 2 + offset(k),
            Self::Abort(k) => 3 + offset(k),
            Self::Cancel => 4,
            Self::PasteLast => 5,
        }
    }

    /// Inverse of [`HotkeyEvent::to_wparam`].
    pub fn from_wparam(w: usize) -> Option<Self> {
        let (kind, base) = if w > Self::COMMAND_OFFSET {
            (TriggerKind::Command, w - Self::COMMAND_OFFSET)
        } else {
            (TriggerKind::Dictation, w)
        };
        match (base, kind) {
            (1, k) => Some(Self::Down(k)),
            (2, k) => Some(Self::Up(k)),
            (3, k) => Some(Self::Abort(k)),
            (4, TriggerKind::Dictation) => Some(Self::Cancel),
            (5, TriggerKind::Dictation) => Some(Self::PasteLast),
            _ => None,
        }
    }
}

/// Matches a generic modifier code against left/right specific ones.
fn same_modifier(configured: u16, pressed: u16) -> bool {
    configured == pressed
        || matches!(
            (configured, pressed),
            (vk::CONTROL, vk::LCONTROL | vk::RCONTROL)
                | (vk::MENU, vk::LMENU | vk::RMENU)
                | (vk::SHIFT, vk::LSHIFT | vk::RSHIFT)
        )
}

/// Whether `code` with the currently held `modifiers` is exactly `hotkey`.
pub fn matches_key(hotkey: Option<Hotkey>, code: u16, modifiers: Modifiers) -> bool {
    matches!(hotkey, Some(Hotkey::Key { vk, modifiers: m }) if vk == code && m == modifiers)
}

/// A bare cancel key (Escape) also fires while modifiers are held.
pub fn matches_cancel(cancel: Option<Hotkey>, code: u16, modifiers: Modifiers) -> bool {
    match cancel {
        Some(Hotkey::Key { vk, modifiers: m }) if m.is_empty() => vk == code,
        other => matches_key(other, code, modifiers),
    }
}

/// One recording shortcut and its press state.
#[derive(Debug, Clone)]
pub struct Trigger {
    kind: TriggerKind,
    hotkey: Option<Hotkey>,
    /// Shortcut currently held down.
    held: bool,
    /// A modifier-only shortcut is held and no other key was pressed meanwhile.
    clean: bool,
}

impl Trigger {
    pub fn new(kind: TriggerKind, hotkey: Option<Hotkey>) -> Self {
        Self { kind, hotkey, held: false, clean: false }
    }

    pub fn hotkey(&self) -> Option<Hotkey> {
        self.hotkey
    }

    /// Processes a key event. `modifiers` are the modifiers held at the time.
    /// Returns whether the event should be swallowed (kept from other apps).
    pub fn on_key(
        &mut self,
        code: u16,
        down: bool,
        modifiers: Modifiers,
        mode: HotkeyMode,
        events: &mut Vec<HotkeyEvent>,
    ) -> bool {
        match self.hotkey {
            Some(Hotkey::ModifierOnly { vk: m }) if same_modifier(m, code) => {
                self.on_own_modifier(down, mode, events);
                false // never swallow modifiers: other shortcuts still need them
            }
            Some(Hotkey::ModifierOnly { .. }) if down && self.held => {
                // Another key while the modifier is held: it's a regular shortcut.
                if self.clean {
                    self.clean = false;
                    if mode != HotkeyMode::Toggle {
                        events.push(HotkeyEvent::Abort(self.kind));
                    }
                }
                false
            }
            Some(Hotkey::Key { vk: k, .. }) if k == code => self.on_own_key(down, modifiers, events),
            _ => false,
        }
    }

    fn on_own_modifier(&mut self, down: bool, mode: HotkeyMode, events: &mut Vec<HotkeyEvent>) {
        if down && !self.held {
            self.held = true;
            self.clean = true;
            if mode != HotkeyMode::Toggle {
                events.push(HotkeyEvent::Down(self.kind));
            }
        } else if !down && self.held {
            self.held = false;
            match mode {
                // Toggle acts on a clean tap so modifier chords (Ctrl+C) don't record.
                HotkeyMode::Toggle if self.clean => events.push(HotkeyEvent::Down(self.kind)),
                HotkeyMode::Toggle => {}
                _ => events.push(HotkeyEvent::Up(self.kind)),
            }
        }
    }

    fn on_own_key(&mut self, down: bool, modifiers: Modifiers, events: &mut Vec<HotkeyEvent>) -> bool {
        if down && !self.held && matches_key(self.hotkey, self.key_code(), modifiers) {
            self.held = true;
            events.push(HotkeyEvent::Down(self.kind));
            true
        } else if down && self.held {
            true // auto-repeat
        } else if !down && self.held {
            self.held = false;
            events.push(HotkeyEvent::Up(self.kind));
            true
        } else {
            false
        }
    }

    fn key_code(&self) -> u16 {
        match self.hotkey {
            Some(Hotkey::Key { vk, .. } | Hotkey::ModifierOnly { vk }) => vk,
            Some(Hotkey::Mouse { button }) => button,
            None => 0,
        }
    }

    /// Processes a mouse button event; returns whether to swallow it.
    pub fn on_mouse(&mut self, button: u16, down: bool, events: &mut Vec<HotkeyEvent>) -> bool {
        if self.hotkey != Some(Hotkey::Mouse { button }) {
            return false;
        }
        if down && !self.held {
            self.held = true;
            events.push(HotkeyEvent::Down(self.kind));
        } else if !down && self.held {
            self.held = false;
            events.push(HotkeyEvent::Up(self.kind));
        }
        true
    }
}

/// All shortcuts the hook watches, plus the cancel and paste-last keys.
#[derive(Debug, Clone)]
pub struct ShortcutSet {
    triggers: [Trigger; 2],
    cancel: Option<Hotkey>,
    paste_last: Option<Hotkey>,
    mode: HotkeyMode,
}

impl ShortcutSet {
    pub fn new(
        record: Option<Hotkey>,
        command: Option<Hotkey>,
        cancel: Option<Hotkey>,
        paste_last: Option<Hotkey>,
        mode: HotkeyMode,
    ) -> Self {
        Self {
            triggers: [Trigger::new(TriggerKind::Dictation, record), Trigger::new(TriggerKind::Command, command)],
            cancel,
            paste_last,
            mode,
        }
    }

    pub fn uses_mouse(&self) -> bool {
        self.triggers.iter().any(|t| matches!(t.hotkey(), Some(Hotkey::Mouse { .. })))
    }

    /// Handles a keyboard event. `active` is true while recording or
    /// processing (enables the cancel key). Returns whether to swallow it.
    pub fn on_key(
        &mut self,
        code: u16,
        down: bool,
        modifiers: Modifiers,
        active: bool,
        events: &mut Vec<HotkeyEvent>,
    ) -> bool {
        let mode = self.mode;
        let mut swallow = false;
        for trigger in &mut self.triggers {
            swallow |= trigger.on_key(code, down, modifiers, mode, events);
        }
        if down && !is_modifier_vk(code) && !swallow {
            if active && matches_cancel(self.cancel, code, modifiers) {
                events.push(HotkeyEvent::Cancel);
                swallow = true;
            } else if matches_key(self.paste_last, code, modifiers) {
                events.push(HotkeyEvent::PasteLast);
                swallow = true;
            }
        }
        swallow
    }

    /// Handles a mouse button event. Returns whether to swallow it.
    pub fn on_mouse(&mut self, button: u16, down: bool, events: &mut Vec<HotkeyEvent>) -> bool {
        let mut swallow = false;
        for trigger in &mut self.triggers {
            swallow |= trigger.on_mouse(button, down, events);
        }
        swallow
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const NONE: Modifiers = Modifiers { ctrl: false, alt: false, shift: false, win: false };
    const CTRL_SHIFT: Modifiers = Modifiers { ctrl: true, alt: false, shift: true, win: false };

    fn set(mode: HotkeyMode) -> ShortcutSet {
        ShortcutSet::new(
            "RightCtrl".parse().ok(),
            "Ctrl+Shift+Space".parse().ok(),
            "Escape".parse().ok(),
            "Alt+Shift+V".parse().ok(),
            mode,
        )
    }

    fn press(s: &mut ShortcutSet, code: u16, down: bool, mods: Modifiers, active: bool) -> (bool, Vec<HotkeyEvent>) {
        let mut events = Vec::new();
        let swallow = s.on_key(code, down, mods, active, &mut events);
        (swallow, events)
    }

    #[test]
    fn modifier_only_hybrid_reports_down_and_up_without_swallowing() {
        let mut s = set(HotkeyMode::Hybrid);
        let (sw, ev) = press(&mut s, vk::RCONTROL, true, NONE, false);
        assert!(!sw);
        assert_eq!(ev, [HotkeyEvent::Down(TriggerKind::Dictation)]);
        // Auto-repeat while held produces nothing.
        assert_eq!(press(&mut s, vk::RCONTROL, true, NONE, false).1, vec![]);
        assert_eq!(press(&mut s, vk::RCONTROL, false, NONE, false).1, [HotkeyEvent::Up(TriggerKind::Dictation)]);
    }

    #[test]
    fn modifier_chord_aborts_the_recording() {
        let mut s = set(HotkeyMode::Hybrid);
        press(&mut s, vk::RCONTROL, true, NONE, false);
        let (sw, ev) = press(&mut s, u16::from(b'C'), true, Modifiers { ctrl: true, ..NONE }, true);
        assert!(!sw, "Ctrl+C must reach the app");
        assert_eq!(ev, [HotkeyEvent::Abort(TriggerKind::Dictation)]);
    }

    #[test]
    fn toggle_mode_fires_on_clean_release_only() {
        let mut s = set(HotkeyMode::Toggle);
        assert_eq!(press(&mut s, vk::RCONTROL, true, NONE, false).1, vec![]);
        assert_eq!(press(&mut s, vk::RCONTROL, false, NONE, false).1, [HotkeyEvent::Down(TriggerKind::Dictation)]);

        press(&mut s, vk::RCONTROL, true, NONE, false);
        press(&mut s, u16::from(b'C'), true, Modifiers { ctrl: true, ..NONE }, false);
        assert_eq!(press(&mut s, vk::RCONTROL, false, NONE, false).1, vec![]);
    }

    #[test]
    fn key_combination_is_swallowed_and_needs_exact_modifiers() {
        let mut s = set(HotkeyMode::Hybrid);
        let (sw, ev) = press(&mut s, vk::SPACE, true, CTRL_SHIFT, false);
        assert!(sw);
        assert_eq!(ev, [HotkeyEvent::Down(TriggerKind::Command)]);
        assert!(press(&mut s, vk::SPACE, true, CTRL_SHIFT, false).0, "auto-repeat is swallowed");
        assert_eq!(press(&mut s, vk::SPACE, false, NONE, false).1, [HotkeyEvent::Up(TriggerKind::Command)]);

        let (sw, ev) = press(&mut s, vk::SPACE, true, Modifiers { ctrl: true, ..NONE }, false);
        assert!(!sw);
        assert_eq!(ev, vec![]);
    }

    #[test]
    fn cancel_only_while_active_and_ignores_modifiers() {
        let mut s = set(HotkeyMode::Hybrid);
        assert_eq!(press(&mut s, vk::ESCAPE, true, NONE, false), (false, vec![]));
        assert_eq!(press(&mut s, vk::ESCAPE, true, CTRL_SHIFT, true), (true, vec![HotkeyEvent::Cancel]));
    }

    #[test]
    fn paste_last_shortcut() {
        let mut s = set(HotkeyMode::Hybrid);
        let alt_shift = Modifiers { alt: true, shift: true, ..NONE };
        assert_eq!(press(&mut s, u16::from(b'V'), true, alt_shift, false), (true, vec![HotkeyEvent::PasteLast]));
    }

    #[test]
    fn mouse_trigger() {
        let mut s = ShortcutSet::new("Mouse4".parse().ok(), None, None, None, HotkeyMode::PushToTalk);
        assert!(s.uses_mouse());
        let mut ev = Vec::new();
        assert!(s.on_mouse(vk::XBUTTON1, true, &mut ev));
        assert!(s.on_mouse(vk::XBUTTON1, false, &mut ev));
        assert!(!s.on_mouse(vk::XBUTTON2, true, &mut ev));
        assert_eq!(ev, [HotkeyEvent::Down(TriggerKind::Dictation), HotkeyEvent::Up(TriggerKind::Dictation)]);
    }

    #[test]
    fn wparam_round_trip() {
        for e in [
            HotkeyEvent::Down(TriggerKind::Dictation),
            HotkeyEvent::Up(TriggerKind::Command),
            HotkeyEvent::Abort(TriggerKind::Command),
            HotkeyEvent::Cancel,
            HotkeyEvent::PasteLast,
        ] {
            assert_eq!(HotkeyEvent::from_wparam(e.to_wparam()), Some(e));
        }
        assert_eq!(HotkeyEvent::from_wparam(0), None);
        assert_eq!(HotkeyEvent::from_wparam(14), None);
    }
}
