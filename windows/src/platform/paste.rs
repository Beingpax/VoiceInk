//! Delivering text into the focused application (port of `CursorPaster`).
//!
//! Must run off the UI thread: every step sleeps briefly so the target
//! application can keep up, like the macOS implementation.

use super::clipboard::{self, Snapshot};
use super::error::{Error, Result};
use crate::config::{OutputSettings, PasteMethod, SendKey};
use std::time::{Duration, Instant};
use windows::Win32::UI::Input::KeyboardAndMouse::{
    GetAsyncKeyState, INPUT, INPUT_0, INPUT_KEYBOARD, KEYBD_EVENT_FLAGS, KEYBDINPUT, KEYEVENTF_EXTENDEDKEY,
    KEYEVENTF_KEYUP, KEYEVENTF_UNICODE, SendInput, VIRTUAL_KEY, VK_C, VK_CONTROL, VK_INSERT, VK_LMENU, VK_LSHIFT,
    VK_LWIN, VK_MENU, VK_RCONTROL, VK_RETURN, VK_RMENU, VK_RSHIFT, VK_RWIN, VK_SHIFT, VK_V,
};

/// Lets the target app settle after the clipboard changed.
const PRE_PASTE_DELAY: Duration = Duration::from_millis(60);
const KEY_EVENT_DELAY: Duration = Duration::from_millis(8);
/// The target must have read the clipboard before we restore it.
const MIN_RESTORE_DELAY: Duration = Duration::from_millis(250);
const SEND_KEY_DELAY_AFTER_PASTE: Duration = Duration::from_millis(150);
const SEND_KEY_DELAY_AFTER_TYPING: Duration = Duration::from_millis(80);
/// Unicode key events sent per `SendInput` call when typing.
const TYPING_BATCH: usize = 200;
const COPY_TIMEOUT: Duration = Duration::from_millis(250);
const COPY_POLL_INTERVAL: Duration = Duration::from_millis(10);
const KEY_DOWN_BIT: u16 = 0x8000;

const BLOCKED_HINT: &str = "is the target app running as administrator?";

fn key(vk: VIRTUAL_KEY, up: bool) -> INPUT {
    let mut flags = KEYBD_EVENT_FLAGS(0);
    if up {
        flags |= KEYEVENTF_KEYUP;
    }
    if matches!(vk, VK_INSERT | VK_RCONTROL | VK_RMENU) {
        flags |= KEYEVENTF_EXTENDEDKEY;
    }
    keyboard_input(KEYBDINPUT { wVk: vk, wScan: 0, dwFlags: flags, time: 0, dwExtraInfo: 0 })
}

fn unicode(unit: u16, up: bool) -> INPUT {
    let mut flags = KEYEVENTF_UNICODE;
    if up {
        flags |= KEYEVENTF_KEYUP;
    }
    keyboard_input(KEYBDINPUT { wVk: VIRTUAL_KEY(0), wScan: unit, dwFlags: flags, time: 0, dwExtraInfo: 0 })
}

fn keyboard_input(ki: KEYBDINPUT) -> INPUT {
    INPUT { r#type: INPUT_KEYBOARD, Anonymous: INPUT_0 { ki } }
}

/// Injects `inputs`; fails when Windows (UIPI) blocks them.
fn send(inputs: &[INPUT]) -> Result<()> {
    // SAFETY: `inputs` is a valid slice of fully initialized INPUT structs.
    let sent = unsafe { SendInput(inputs, size_of::<INPUT>() as i32) };
    if sent as usize == inputs.len() {
        Ok(())
    } else {
        Err(Error::Message(format!("Windows blocked the keystrokes ({BLOCKED_HINT})")))
    }
}

fn is_down(vk: VIRTUAL_KEY) -> bool {
    // SAFETY: GetAsyncKeyState has no preconditions.
    (unsafe { GetAsyncKeyState(i32::from(vk.0)) }).cast_unsigned() & KEY_DOWN_BIT != 0
}

/// Releases modifiers the user may still be holding (e.g. a Ctrl+Shift hotkey),
/// otherwise Ctrl+V could arrive as Ctrl+Shift+V.
fn release_held_modifiers() {
    let held: Vec<INPUT> = [VK_LSHIFT, VK_RSHIFT, VK_LMENU, VK_RMENU, VK_LWIN, VK_RWIN, VK_SHIFT, VK_MENU]
        .into_iter()
        .filter(|&vk| is_down(vk))
        .map(|vk| key(vk, true))
        .collect();
    if !held.is_empty() {
        let _ = send(&held);
    }
}

/// Sends `modifier+key` with small pauses, like `pasteFromClipboard` does with `CGEvents`.
fn chord(modifier: VIRTUAL_KEY, k: VIRTUAL_KEY) -> Result<()> {
    for input in [key(modifier, false), key(k, false), key(k, true), key(modifier, true)] {
        send(std::slice::from_ref(&input))?;
        std::thread::sleep(KEY_EVENT_DELAY);
    }
    Ok(())
}

/// Types `text` as Unicode key events. Newlines become Return presses
/// because many apps ignore a Unicode "\n".
fn type_text(text: &str) -> Result<()> {
    let mut batch = Vec::with_capacity(TYPING_BATCH);
    for ch in text.replace("\r\n", "\n").chars() {
        if ch == '\n' {
            send(&batch)?;
            batch.clear();
            send(&[key(VK_RETURN, false), key(VK_RETURN, true)])?;
            continue;
        }
        let mut buf = [0u16; 2];
        for &unit in ch.encode_utf16(&mut buf).iter() {
            batch.extend([unicode(unit, false), unicode(unit, true)]);
        }
        if batch.len() >= TYPING_BATCH {
            send(&batch)?;
            batch.clear();
            std::thread::sleep(KEY_EVENT_DELAY);
        }
    }
    if batch.is_empty() { Ok(()) } else { send(&batch) }
}

/// "Finish & Send": presses Enter (optionally with a modifier) after pasting.
pub fn press_send_key(send_key: SendKey) {
    let result = match send_key {
        SendKey::None => Ok(()),
        SendKey::Enter => send(&[key(VK_RETURN, false), key(VK_RETURN, true)]),
        SendKey::ShiftEnter => chord(VK_SHIFT, VK_RETURN),
        SendKey::CtrlEnter => chord(VK_CONTROL, VK_RETURN),
    };
    if let Err(e) = result {
        log::warn!("send key failed: {e}");
    }
}

/// Inserts `text` into the focused control with the configured method.
///
/// # Errors
/// Fails when Windows blocks the simulated input or the clipboard is busy.
pub fn paste_text(text: &str, settings: &OutputSettings, send_key: SendKey) -> Result<()> {
    let mut text = text.to_string();
    if settings.append_space && !text.ends_with(char::is_whitespace) {
        text.push(' ');
    }
    release_held_modifiers();
    match settings.method {
        PasteMethod::Type => type_into_target(&text, send_key),
        PasteMethod::CtrlV => paste_via_clipboard(&text, settings, send_key, (VK_CONTROL, VK_V)),
        PasteMethod::ShiftInsert => paste_via_clipboard(&text, settings, send_key, (VK_SHIFT, VK_INSERT)),
    }
}

fn type_into_target(text: &str, send_key: SendKey) -> Result<()> {
    std::thread::sleep(PRE_PASTE_DELAY);
    type_text(text)?;
    if send_key != SendKey::None {
        std::thread::sleep(SEND_KEY_DELAY_AFTER_TYPING);
        press_send_key(send_key);
    }
    Ok(())
}

fn paste_via_clipboard(
    text: &str,
    settings: &OutputSettings,
    send_key: SendKey,
    (modifier, paste_key): (VIRTUAL_KEY, VIRTUAL_KEY),
) -> Result<()> {
    let snapshot = settings.restore_clipboard.then(Snapshot::capture);
    let sequence = clipboard::set_text(text, settings.restore_clipboard)?;
    std::thread::sleep(PRE_PASTE_DELAY);

    let pasted = chord(modifier, paste_key);
    if pasted.is_ok() && send_key != SendKey::None {
        std::thread::sleep(SEND_KEY_DELAY_AFTER_PASTE);
        press_send_key(send_key);
    }

    if let Some(snapshot) = snapshot {
        std::thread::sleep(Duration::from_millis(settings.clipboard_restore_delay_ms).max(MIN_RESTORE_DELAY));
        // Only restore if nobody (user or app) changed the clipboard since our paste.
        if clipboard::sequence_number() == sequence
            && let Err(e) = snapshot.restore()
        {
            log::warn!("clipboard restore failed: {e}");
        }
    }
    pasted.map_err(|_| {
        Error::Message(format!("Windows blocked the paste keystroke ({BLOCKED_HINT}). The text is on the clipboard."))
    })
}

/// Copies the focused app's selection via Ctrl+C and returns it, then
/// restores the previous clipboard (used for Command Mode and AI context).
pub fn copy_selection() -> Option<String> {
    let snapshot = Snapshot::capture();
    let before = clipboard::sequence_number();
    // A held Shift/Alt from a shortcut like Ctrl+Shift+Space would turn Ctrl+C
    // into another command (Ctrl+Shift+C opens DevTools in browsers).
    release_held_modifiers();
    // Always send a complete Ctrl+C chord: relying on a physically held Ctrl
    // races with the user releasing the shortcut, and a bare "c" would then
    // overwrite the selection.
    chord(VK_CONTROL, VK_C).ok()?;

    let deadline = Instant::now() + COPY_TIMEOUT;
    while clipboard::sequence_number() == before && Instant::now() < deadline {
        std::thread::sleep(COPY_POLL_INTERVAL);
    }
    if clipboard::sequence_number() == before {
        return None; // Nothing selected (or the app ignored Ctrl+C).
    }
    let selected = clipboard::get_text();
    let _ = snapshot.restore();
    selected.filter(|s| !s.trim().is_empty())
}
