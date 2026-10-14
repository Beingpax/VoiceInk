//! Global shortcuts via low-level keyboard/mouse hooks (`ShortcutMonitor`).
//!
//! `RegisterHotKey` cannot express modifier-only shortcuts (Right Ctrl) or
//! key-release events, both of which push-to-talk needs, so we use
//! `WH_KEYBOARD_LL`/`WH_MOUSE_LL`. The hook procedures run on the UI thread
//! (the one that installed them), stay tiny and only post messages.

use crate::config::{
    is_modifier_vk, parse_hotkey, vk, Hotkey, HotkeyMode, HotkeySettings, Modifiers,
};
use std::cell::{Cell, RefCell};
use windows::Win32::Foundation::{HWND, LPARAM, LRESULT, WPARAM};
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::UI::Input::KeyboardAndMouse::GetAsyncKeyState;
use windows::Win32::UI::WindowsAndMessaging::{
    CallNextHookEx, PostMessageW, SetWindowsHookExW, UnhookWindowsHookEx, HC_ACTION, HHOOK,
    KBDLLHOOKSTRUCT, LLKHF_INJECTED, MSLLHOOKSTRUCT, WH_KEYBOARD_LL, WH_MOUSE_LL, WM_APP,
    WM_KEYDOWN, WM_KEYUP, WM_MBUTTONDOWN, WM_MBUTTONUP, WM_SYSKEYDOWN, WM_SYSKEYUP, WM_XBUTTONDOWN,
    WM_XBUTTONUP,
};

/// Posted to the app window; `wParam` is a [`HotkeyEvent`].
pub const WM_HOTKEY_EVENT: u32 = WM_APP + 1;

/// Which recording a shortcut starts.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TriggerKind {
    /// Normal dictation.
    Dictation,
    /// Command Mode: the speech is an instruction for the selected text.
    Command,
}

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
    fn to_wparam(self) -> usize {
        let kind = |k: TriggerKind| if k == TriggerKind::Command { 10 } else { 0 };
        match self {
            Self::Down(k) => 1 + kind(k),
            Self::Up(k) => 2 + kind(k),
            Self::Abort(k) => 3 + kind(k),
            Self::Cancel => 4,
            Self::PasteLast => 5,
        }
    }

    pub fn from_wparam(w: usize) -> Option<Self> {
        let kind = if w > 10 {
            TriggerKind::Command
        } else {
            TriggerKind::Dictation
        };
        Some(match w {
            1 | 11 => Self::Down(kind),
            2 | 12 => Self::Up(kind),
            3 | 13 => Self::Abort(kind),
            4 => Self::Cancel,
            5 => Self::PasteLast,
            _ => return None,
        })
    }
}

/// One recording shortcut and its press state.
struct Trigger {
    kind: TriggerKind,
    hotkey: Option<Hotkey>,
    /// Shortcut currently held down.
    held: bool,
    /// A modifier-only shortcut is held and no other key was pressed meanwhile.
    clean: bool,
}

impl Trigger {
    fn new(kind: TriggerKind, hotkey: Option<Hotkey>) -> Self {
        Self {
            kind,
            hotkey,
            held: false,
            clean: false,
        }
    }

    /// Updates the press state for a key event; returns whether to swallow it.
    fn on_key(
        &mut self,
        code: u16,
        down: bool,
        mode: HotkeyMode,
        events: &mut Vec<HotkeyEvent>,
    ) -> bool {
        let kind = self.kind;
        match self.hotkey {
            Some(Hotkey::ModifierOnly { vk: m }) if same_modifier(m, code) => {
                if down && !self.held {
                    self.held = true;
                    self.clean = true;
                    if mode != HotkeyMode::Toggle {
                        events.push(HotkeyEvent::Down(kind));
                    }
                } else if !down && self.held {
                    self.held = false;
                    if mode == HotkeyMode::Toggle {
                        if self.clean {
                            events.push(HotkeyEvent::Down(kind));
                        }
                    } else {
                        events.push(HotkeyEvent::Up(kind));
                    }
                }
                // Never swallow modifiers: other shortcuts still need them.
                false
            }
            Some(Hotkey::ModifierOnly { .. }) if down && self.held => {
                // Another key while the modifier is held: it's a regular shortcut.
                if self.clean {
                    self.clean = false;
                    if mode != HotkeyMode::Toggle {
                        events.push(HotkeyEvent::Abort(kind));
                    }
                }
                false
            }
            Some(Hotkey::Key { vk: k, .. }) if k == code => {
                if down && !self.held && matches_key(self.hotkey, code) {
                    self.held = true;
                    events.push(HotkeyEvent::Down(kind));
                    true
                } else if down && self.held {
                    true // auto-repeat
                } else if !down && self.held {
                    self.held = false;
                    events.push(HotkeyEvent::Up(kind));
                    true
                } else {
                    false
                }
            }
            _ => false,
        }
    }

    fn on_mouse(&mut self, button: u16, down: bool, events: &mut Vec<HotkeyEvent>) -> bool {
        let Some(Hotkey::Mouse { button: b }) = self.hotkey else {
            return false;
        };
        if b != button {
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

struct HookState {
    hwnd: HWND,
    triggers: [Trigger; 2],
    cancel: Option<Hotkey>,
    paste_last: Option<Hotkey>,
    mode: HotkeyMode,
}

thread_local! {
    static STATE: RefCell<Option<HookState>> = const { RefCell::new(None) };
    static HOOKS: RefCell<Vec<HHOOK>> = const { RefCell::new(Vec::new()) };
    /// True while recording or processing; enables the cancel shortcut.
    static ACTIVE: Cell<bool> = const { Cell::new(false) };
}

fn post(event: HotkeyEvent) {
    STATE.with(|s| {
        if let Some(state) = s.borrow().as_ref() {
            unsafe {
                let _ = PostMessageW(
                    Some(state.hwnd),
                    WM_HOTKEY_EVENT,
                    WPARAM(event.to_wparam()),
                    LPARAM(0),
                );
            }
        }
    });
}

fn key_down(code: u16) -> bool {
    unsafe { GetAsyncKeyState(code as i32) as u16 & 0x8000 != 0 }
}

fn current_modifiers() -> Modifiers {
    Modifiers {
        ctrl: key_down(vk::CONTROL),
        alt: key_down(vk::MENU),
        shift: key_down(vk::SHIFT),
        win: key_down(vk::LWIN) || key_down(vk::RWIN),
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

fn matches_key(hotkey: Option<Hotkey>, code: u16) -> bool {
    match hotkey {
        Some(Hotkey::Key { vk, modifiers }) => vk == code && current_modifiers() == modifiers,
        _ => false,
    }
}

/// Returns true to swallow the event.
fn handle_key(code: u16, down: bool) -> bool {
    STATE.with(|s| {
        let mut guard = s.borrow_mut();
        let Some(state) = guard.as_mut() else {
            return false;
        };
        let mut events = Vec::new();
        let mode = state.mode;
        let mut swallow = false;
        for trigger in state.triggers.iter_mut() {
            swallow |= trigger.on_key(code, down, mode, &mut events);
        }

        if down && !is_modifier_vk(code) && !swallow {
            if ACTIVE.with(Cell::get) && is_cancel(state.cancel, code) {
                events.push(HotkeyEvent::Cancel);
                swallow = true;
            } else if matches_key(state.paste_last, code) {
                events.push(HotkeyEvent::PasteLast);
                swallow = true;
            }
        }
        drop(guard);
        for e in events {
            post(e);
        }
        swallow
    })
}

fn is_cancel(cancel: Option<Hotkey>, code: u16) -> bool {
    match cancel {
        // A bare cancel key (Escape) also fires while modifiers are held.
        Some(Hotkey::Key { vk, modifiers }) if modifiers.is_empty() => vk == code,
        other => matches_key(other, code),
    }
}

fn handle_mouse(button: u16, down: bool) -> bool {
    STATE.with(|s| {
        let mut guard = s.borrow_mut();
        let Some(state) = guard.as_mut() else {
            return false;
        };
        let mut events = Vec::new();
        let mut swallow = false;
        for trigger in state.triggers.iter_mut() {
            swallow |= trigger.on_mouse(button, down, &mut events);
        }
        drop(guard);
        for e in events {
            post(e);
        }
        swallow
    })
}

unsafe extern "system" fn keyboard_proc(code: i32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    if code == HC_ACTION as i32 {
        let info = &*(lparam.0 as *const KBDLLHOOKSTRUCT);
        // Ignore synthetic input, including our own Ctrl+V / typing.
        if info.flags.0 & LLKHF_INJECTED.0 == 0 {
            let msg = wparam.0 as u32;
            let down = msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN;
            let up = msg == WM_KEYUP || msg == WM_SYSKEYUP;
            if (down || up) && handle_key(info.vkCode as u16, down) {
                return LRESULT(1);
            }
        }
    }
    CallNextHookEx(None, code, wparam, lparam)
}

unsafe extern "system" fn mouse_proc(code: i32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    if code == HC_ACTION as i32 {
        let info = &*(lparam.0 as *const MSLLHOOKSTRUCT);
        const LLMHF_INJECTED: u32 = 0x1;
        if info.flags & LLMHF_INJECTED == 0 {
            let msg = wparam.0 as u32;
            let button = match msg {
                WM_XBUTTONDOWN | WM_XBUTTONUP => match (info.mouseData >> 16) as u16 {
                    1 => Some(vk::XBUTTON1),
                    2 => Some(vk::XBUTTON2),
                    _ => None,
                },
                WM_MBUTTONDOWN | WM_MBUTTONUP => Some(vk::MBUTTON),
                _ => None,
            };
            if let Some(b) = button {
                let down = msg == WM_XBUTTONDOWN || msg == WM_MBUTTONDOWN;
                if handle_mouse(b, down) {
                    return LRESULT(1);
                }
            }
        }
    }
    CallNextHookEx(None, code, wparam, lparam)
}

fn parse_optional(spec: Option<&str>, what: &str, errors: &mut Vec<String>) -> Option<Hotkey> {
    let spec = spec?.trim();
    if spec.is_empty() {
        return None;
    }
    match parse_hotkey(spec) {
        Ok(h) => Some(h),
        Err(e) => {
            errors.push(format!("{what} hotkey '{spec}': {e}"));
            None
        }
    }
}

/// Installs (or re-configures) the hooks. `command` is the Command Mode
/// shortcut, if enabled. Returns configuration problems.
pub fn install(
    hwnd: HWND,
    settings: &HotkeySettings,
    command: Option<&str>,
) -> Result<Vec<String>, String> {
    let mut errors = Vec::new();
    let record = parse_optional(Some(&settings.record), "record", &mut errors);
    let mut command = parse_optional(command, "command", &mut errors);
    if command.is_some() && command == record {
        errors.push("the Command Mode shortcut must differ from the record shortcut".into());
        command = None;
    }
    let cancel = parse_optional(Some(&settings.cancel), "cancel", &mut errors);
    let paste_last = parse_optional(settings.paste_last.as_deref(), "paste-last", &mut errors);
    let needs_mouse = [record, command]
        .iter()
        .any(|h| matches!(h, Some(Hotkey::Mouse { .. })));

    STATE.with(|s| {
        *s.borrow_mut() = Some(HookState {
            hwnd,
            triggers: [
                Trigger::new(TriggerKind::Dictation, record),
                Trigger::new(TriggerKind::Command, command),
            ],
            cancel,
            paste_last,
            mode: settings.mode,
        })
    });

    uninstall_hooks();
    unsafe {
        let module = GetModuleHandleW(None).map_err(|e| e.to_string())?;
        let kb = SetWindowsHookExW(WH_KEYBOARD_LL, Some(keyboard_proc), Some(module.into()), 0)
            .map_err(|e| format!("keyboard hook: {e}"))?;
        HOOKS.with(|h| h.borrow_mut().push(kb));
        if needs_mouse {
            let ms = SetWindowsHookExW(WH_MOUSE_LL, Some(mouse_proc), Some(module.into()), 0)
                .map_err(|e| format!("mouse hook: {e}"))?;
            HOOKS.with(|h| h.borrow_mut().push(ms));
        }
    }
    Ok(errors)
}

fn uninstall_hooks() {
    HOOKS.with(|h| {
        for hook in h.borrow_mut().drain(..) {
            unsafe {
                let _ = UnhookWindowsHookEx(hook);
            }
        }
    });
}

pub fn uninstall() {
    uninstall_hooks();
    STATE.with(|s| *s.borrow_mut() = None);
}

/// Tells the hook whether a recording/transcription is active (enables cancel).
pub fn set_active(active: bool) {
    ACTIVE.with(|a| a.set(active));
}

/// Human-readable description of the record shortcut for menus and tooltips.
pub fn describe(settings: &HotkeySettings) -> String {
    let mode = match settings.mode {
        HotkeyMode::Toggle => "toggle",
        HotkeyMode::PushToTalk => "hold to talk",
        HotkeyMode::Hybrid => "tap to toggle, hold to talk",
    };
    format!("{} ({mode})", settings.record)
}
