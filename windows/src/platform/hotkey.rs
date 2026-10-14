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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(usize)]
pub enum HotkeyEvent {
    /// The record shortcut was pressed (or, for toggle-on-release, tapped).
    RecordDown = 1,
    RecordUp = 2,
    /// A modifier-only shortcut turned out to be part of another shortcut.
    RecordAbort = 3,
    Cancel = 4,
    PasteLast = 5,
}

impl HotkeyEvent {
    pub fn from_wparam(w: usize) -> Option<Self> {
        Some(match w {
            1 => Self::RecordDown,
            2 => Self::RecordUp,
            3 => Self::RecordAbort,
            4 => Self::Cancel,
            5 => Self::PasteLast,
            _ => return None,
        })
    }
}

struct HookState {
    hwnd: HWND,
    record: Option<Hotkey>,
    cancel: Option<Hotkey>,
    paste_last: Option<Hotkey>,
    mode: HotkeyMode,
    /// Record key currently held down.
    record_held: bool,
    /// A modifier-only shortcut is held and no other key was pressed meanwhile.
    modifier_clean: bool,
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
                    WPARAM(event as usize),
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
        let mut swallow = false;

        match state.record {
            Some(Hotkey::ModifierOnly { vk: rec }) if same_modifier(rec, code) => {
                if down && !state.record_held {
                    state.record_held = true;
                    state.modifier_clean = true;
                    if state.mode != HotkeyMode::Toggle {
                        events.push(HotkeyEvent::RecordDown);
                    }
                } else if !down && state.record_held {
                    state.record_held = false;
                    if state.mode == HotkeyMode::Toggle {
                        if state.modifier_clean {
                            events.push(HotkeyEvent::RecordDown);
                        }
                    } else {
                        events.push(HotkeyEvent::RecordUp);
                    }
                }
                // Never swallow modifiers: other shortcuts still need them.
            }
            Some(Hotkey::ModifierOnly { .. }) if down && state.record_held => {
                // Another key while the modifier is held: it's a regular shortcut.
                if state.modifier_clean {
                    state.modifier_clean = false;
                    if state.mode != HotkeyMode::Toggle {
                        events.push(HotkeyEvent::RecordAbort);
                    }
                }
            }
            Some(Hotkey::Key { vk: rec, .. }) if rec == code => {
                if down && !state.record_held && matches_key(state.record, code) {
                    state.record_held = true;
                    events.push(HotkeyEvent::RecordDown);
                    swallow = true;
                } else if down && state.record_held {
                    swallow = true; // auto-repeat
                } else if !down && state.record_held {
                    state.record_held = false;
                    events.push(HotkeyEvent::RecordUp);
                    swallow = true;
                }
            }
            _ => {}
        }

        if down && !is_modifier_vk(code) {
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
        let Some(Hotkey::Mouse { button: rec }) = state.record else {
            return false;
        };
        if rec != button {
            return false;
        }
        let event = if down && !state.record_held {
            state.record_held = true;
            Some(HotkeyEvent::RecordDown)
        } else if !down && state.record_held {
            state.record_held = false;
            Some(HotkeyEvent::RecordUp)
        } else {
            None
        };
        drop(guard);
        if let Some(e) = event {
            post(e);
        }
        true
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

/// Installs (or re-configures) the hooks. Returns configuration problems.
pub fn install(hwnd: HWND, settings: &HotkeySettings) -> Result<Vec<String>, String> {
    let mut errors = Vec::new();
    let record = parse_optional(Some(&settings.record), "record", &mut errors);
    let cancel = parse_optional(Some(&settings.cancel), "cancel", &mut errors);
    let paste_last = parse_optional(settings.paste_last.as_deref(), "paste-last", &mut errors);
    let needs_mouse = matches!(record, Some(Hotkey::Mouse { .. }));

    STATE.with(|s| {
        *s.borrow_mut() = Some(HookState {
            hwnd,
            record,
            cancel,
            paste_last,
            mode: settings.mode,
            record_held: false,
            modifier_clean: false,
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
