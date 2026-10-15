//! Global shortcuts via low-level keyboard/mouse hooks (`ShortcutMonitor`).
//!
//! `RegisterHotKey` cannot express modifier-only shortcuts (Right Ctrl) or
//! key-release events, both of which push-to-talk needs, so we use
//! `WH_KEYBOARD_LL`/`WH_MOUSE_LL`. This module only installs the hooks and
//! forwards raw events to [`ShortcutSet`]; the hook procedures run on the UI
//! thread (the one that installed them), stay tiny and only post messages.

use super::error::{Context, Result};
use crate::config::HotkeySettings;
use crate::input::{Hotkey, HotkeyError, HotkeyEvent, Modifiers, ShortcutSet, vk};
use std::cell::{Cell, RefCell};
use windows::Win32::Foundation::{HWND, LPARAM, LRESULT, WPARAM};
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::UI::Input::KeyboardAndMouse::GetAsyncKeyState;
use windows::Win32::UI::WindowsAndMessaging::{
    CallNextHookEx, HC_ACTION, HHOOK, KBDLLHOOKSTRUCT, LLKHF_INJECTED, MSLLHOOKSTRUCT, PostMessageW, SetWindowsHookExW,
    UnhookWindowsHookEx, WH_KEYBOARD_LL, WH_MOUSE_LL, WM_APP, WM_KEYDOWN, WM_KEYUP, WM_MBUTTONDOWN, WM_MBUTTONUP,
    WM_SYSKEYDOWN, WM_SYSKEYUP, WM_XBUTTONDOWN, WM_XBUTTONUP,
};

/// Posted to the app window; `wParam` is a [`HotkeyEvent::to_wparam`] value.
pub const WM_HOTKEY_EVENT: u32 = WM_APP + 1;

/// `MSLLHOOKSTRUCT::flags` bit for synthetic mouse input.
const LLMHF_INJECTED: u32 = 0x1;
const KEY_DOWN_BIT: u16 = 0x8000;

struct HookState {
    hwnd: HWND,
    shortcuts: ShortcutSet,
}

thread_local! {
    static STATE: RefCell<Option<HookState>> = const { RefCell::new(None) };
    static HOOKS: RefCell<Vec<HHOOK>> = const { RefCell::new(Vec::new()) };
    /// True while recording or processing; enables the cancel shortcut.
    static ACTIVE: Cell<bool> = const { Cell::new(false) };
}

fn key_down(code: u16) -> bool {
    // SAFETY: GetAsyncKeyState has no preconditions.
    (unsafe { GetAsyncKeyState(i32::from(code)) }).cast_unsigned() & KEY_DOWN_BIT != 0
}

fn current_modifiers() -> Modifiers {
    Modifiers {
        ctrl: key_down(vk::CONTROL),
        alt: key_down(vk::MENU),
        shift: key_down(vk::SHIFT),
        win: key_down(vk::LWIN) || key_down(vk::RWIN),
    }
}

/// Runs `f` on the hook state and posts the resulting events. Returns
/// whether to swallow the input.
fn dispatch(f: impl FnOnce(&mut ShortcutSet, &mut Vec<HotkeyEvent>) -> bool) -> bool {
    STATE.with(|cell| {
        let mut guard = cell.borrow_mut();
        let Some(state) = guard.as_mut() else { return false };
        let mut events = Vec::new();
        let swallow = f(&mut state.shortcuts, &mut events);
        for event in events {
            // SAFETY: posting to our own window handle; failure only drops the event.
            let _ = unsafe { PostMessageW(Some(state.hwnd), WM_HOTKEY_EVENT, WPARAM(event.to_wparam()), LPARAM(0)) };
        }
        swallow
    })
}

unsafe extern "system" fn keyboard_proc(code: i32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    if code == HC_ACTION.cast_signed() {
        // SAFETY: for HC_ACTION, lParam points to a KBDLLHOOKSTRUCT valid for this call.
        let info = unsafe { &*(lparam.0 as *const KBDLLHOOKSTRUCT) };
        // Ignore synthetic input, including our own Ctrl+V / typing.
        if info.flags.0 & LLKHF_INJECTED.0 == 0 {
            let msg = u32::try_from(wparam.0).unwrap_or_default();
            let down = msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN;
            let up = msg == WM_KEYUP || msg == WM_SYSKEYUP;
            let vk = u16::try_from(info.vkCode).unwrap_or_default();
            if (down || up)
                && dispatch(|s, events| s.on_key(vk, down, current_modifiers(), ACTIVE.with(Cell::get), events))
            {
                return LRESULT(1);
            }
        }
    }
    // SAFETY: forwarding the unmodified hook arguments.
    unsafe { CallNextHookEx(None, code, wparam, lparam) }
}

unsafe extern "system" fn mouse_proc(code: i32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    if code == HC_ACTION.cast_signed() {
        // SAFETY: for HC_ACTION, lParam points to an MSLLHOOKSTRUCT valid for this call.
        let info = unsafe { &*(lparam.0 as *const MSLLHOOKSTRUCT) };
        if info.flags & LLMHF_INJECTED == 0 {
            let msg = u32::try_from(wparam.0).unwrap_or_default();
            let button = match msg {
                WM_XBUTTONDOWN | WM_XBUTTONUP => match info.mouseData >> 16 {
                    1 => Some(vk::XBUTTON1),
                    2 => Some(vk::XBUTTON2),
                    _ => None,
                },
                WM_MBUTTONDOWN | WM_MBUTTONUP => Some(vk::MBUTTON),
                _ => None,
            };
            let down = msg == WM_XBUTTONDOWN || msg == WM_MBUTTONDOWN;
            if button.is_some_and(|b| dispatch(|s, events| s.on_mouse(b, down, events))) {
                return LRESULT(1);
            }
        }
    }
    // SAFETY: forwarding the unmodified hook arguments.
    unsafe { CallNextHookEx(None, code, wparam, lparam) }
}

/// A shortcut that could not be parsed; it is disabled until fixed.
#[derive(Debug)]
pub struct ShortcutProblem {
    pub which: &'static str,
    pub spec: String,
    pub error: HotkeyError,
}

impl std::fmt::Display for ShortcutProblem {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{} shortcut '{}': {}", self.which, self.spec, self.error)
    }
}

fn parse_optional(spec: Option<&str>, which: &'static str, problems: &mut Vec<ShortcutProblem>) -> Option<Hotkey> {
    let spec = spec.map(str::trim).filter(|s| !s.is_empty())?;
    spec.parse().map_err(|error| problems.push(ShortcutProblem { which, spec: spec.to_string(), error })).ok()
}

/// Installs (or re-configures) the hooks. `command` is the Command Mode
/// shortcut, if enabled. Returns the shortcuts that could not be parsed.
///
/// # Errors
/// Fails when Windows refuses to install a hook.
pub fn install(hwnd: HWND, settings: &HotkeySettings, command: Option<&str>) -> Result<Vec<ShortcutProblem>> {
    let mut problems = Vec::new();
    let record = parse_optional(Some(&settings.record), "Record", &mut problems);
    let mut command = parse_optional(command, "Command", &mut problems);
    if command.is_some() && command == record {
        log::warn!("Command Mode shortcut equals the record shortcut; ignoring it");
        command = None;
    }
    let cancel = parse_optional(Some(&settings.cancel), "Cancel", &mut problems);
    let paste_last = parse_optional(settings.paste_last.as_deref(), "Paste-last", &mut problems);
    let shortcuts = ShortcutSet::new(record, command, cancel, paste_last, settings.mode);
    let needs_mouse = shortcuts.uses_mouse();
    STATE.with(|s| *s.borrow_mut() = Some(HookState { hwnd, shortcuts }));

    uninstall_hooks();
    // SAFETY: GetModuleHandleW(None) returns this executable's module.
    let module = unsafe { GetModuleHandleW(None) }.context("module handle")?;
    // SAFETY: the hook procedures are `extern "system"` functions with the
    // documented signatures and live for the whole program.
    let keyboard = unsafe { SetWindowsHookExW(WH_KEYBOARD_LL, Some(keyboard_proc), Some(module.into()), 0) }
        .context("keyboard hook")?;
    HOOKS.with(|h| h.borrow_mut().push(keyboard));
    if needs_mouse {
        // SAFETY: as above.
        let mouse = unsafe { SetWindowsHookExW(WH_MOUSE_LL, Some(mouse_proc), Some(module.into()), 0) }
            .context("mouse hook")?;
        HOOKS.with(|h| h.borrow_mut().push(mouse));
    }
    Ok(problems)
}

fn uninstall_hooks() {
    HOOKS.with(|h| {
        for hook in h.borrow_mut().drain(..) {
            // SAFETY: `hook` was returned by SetWindowsHookExW and is unhooked once.
            let _ = unsafe { UnhookWindowsHookEx(hook) };
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
