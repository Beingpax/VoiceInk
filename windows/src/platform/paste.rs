//! Delivering text into the focused application (port of `CursorPaster`).

use super::clipboard::{self, Snapshot};
use crate::config::{OutputSettings, PasteMethod, SendKey};
use std::time::Duration;
use windows::Win32::UI::Input::KeyboardAndMouse::{
    GetAsyncKeyState, SendInput, INPUT, INPUT_0, INPUT_KEYBOARD, KEYBDINPUT, KEYBD_EVENT_FLAGS,
    KEYEVENTF_EXTENDEDKEY, KEYEVENTF_KEYUP, KEYEVENTF_UNICODE, VIRTUAL_KEY, VK_C, VK_CONTROL,
    VK_INSERT, VK_LMENU, VK_LSHIFT, VK_LWIN, VK_MENU, VK_RCONTROL, VK_RETURN, VK_RMENU, VK_RSHIFT,
    VK_RWIN, VK_SHIFT, VK_V,
};

const PRE_PASTE_DELAY: Duration = Duration::from_millis(60);
const KEY_EVENT_DELAY: Duration = Duration::from_millis(8);
const MIN_RESTORE_DELAY: Duration = Duration::from_millis(250);

fn key(vk: VIRTUAL_KEY, up: bool) -> INPUT {
    let extended = matches!(vk, VK_INSERT | VK_RCONTROL | VK_RMENU);
    let mut flags = KEYBD_EVENT_FLAGS(0);
    if up {
        flags |= KEYEVENTF_KEYUP;
    }
    if extended {
        flags |= KEYEVENTF_EXTENDEDKEY;
    }
    INPUT {
        r#type: INPUT_KEYBOARD,
        Anonymous: INPUT_0 {
            ki: KEYBDINPUT {
                wVk: vk,
                wScan: 0,
                dwFlags: flags,
                time: 0,
                dwExtraInfo: 0,
            },
        },
    }
}

fn unicode(unit: u16, up: bool) -> INPUT {
    let mut flags = KEYEVENTF_UNICODE;
    if up {
        flags |= KEYEVENTF_KEYUP;
    }
    INPUT {
        r#type: INPUT_KEYBOARD,
        Anonymous: INPUT_0 {
            ki: KEYBDINPUT {
                wVk: VIRTUAL_KEY(0),
                wScan: unit,
                dwFlags: flags,
                time: 0,
                dwExtraInfo: 0,
            },
        },
    }
}

fn send(inputs: &[INPUT]) -> bool {
    let sent = unsafe { SendInput(inputs, std::mem::size_of::<INPUT>() as i32) };
    sent as usize == inputs.len()
}

/// Releases modifiers the user may still be holding (e.g. a Ctrl+Shift hotkey),
/// otherwise Ctrl+V could arrive as Ctrl+Shift+V.
fn release_held_modifiers() {
    let mods = [
        VK_LSHIFT, VK_RSHIFT, VK_LMENU, VK_RMENU, VK_LWIN, VK_RWIN, VK_SHIFT, VK_MENU,
    ];
    let held: Vec<INPUT> = mods
        .iter()
        .filter(|vk| unsafe { GetAsyncKeyState(vk.0 as i32) } as u16 & 0x8000 != 0)
        .map(|&vk| key(vk, true))
        .collect();
    if !held.is_empty() {
        send(&held);
    }
}

/// Sends a chord with small pauses, like `pasteFromClipboard` does with CGEvents.
fn chord(modifier: VIRTUAL_KEY, k: VIRTUAL_KEY) -> bool {
    let steps = [
        key(modifier, false),
        key(k, false),
        key(k, true),
        key(modifier, true),
    ];
    steps.iter().all(|input| {
        let ok = send(std::slice::from_ref(input));
        std::thread::sleep(KEY_EVENT_DELAY);
        ok
    })
}

fn type_text(text: &str) -> bool {
    // Normalize line endings: a bare "\n" as a Unicode event is ignored by many
    // apps, so newlines are sent as Return key presses.
    let mut ok = true;
    let mut batch: Vec<INPUT> = Vec::new();
    let flush = |batch: &mut Vec<INPUT>| {
        let r = batch.is_empty() || send(batch);
        batch.clear();
        r
    };
    for ch in text.replace("\r\n", "\n").chars() {
        if ch == '\n' {
            ok &= flush(&mut batch);
            ok &= send(&[key(VK_RETURN, false), key(VK_RETURN, true)]);
            continue;
        }
        let mut buf = [0u16; 2];
        for &unit in ch.encode_utf16(&mut buf).iter() {
            batch.push(unicode(unit, false));
            batch.push(unicode(unit, true));
        }
        if batch.len() >= 200 {
            ok &= flush(&mut batch);
            std::thread::sleep(KEY_EVENT_DELAY);
        }
    }
    ok &= flush(&mut batch);
    ok
}

/// "Finish & Send": presses Enter (optionally with a modifier) after pasting.
pub fn press_send_key(send_key: SendKey) {
    let enter = [key(VK_RETURN, false), key(VK_RETURN, true)];
    match send_key {
        SendKey::None => {}
        SendKey::Enter => {
            send(&enter);
        }
        SendKey::ShiftEnter => {
            chord(VK_SHIFT, VK_RETURN);
        }
        SendKey::CtrlEnter => {
            chord(VK_CONTROL, VK_RETURN);
        }
    }
}

/// Pastes `text` into the focused control. Must run off the UI thread: it
/// sleeps between steps and the clipboard restore waits for the target app.
pub fn paste_text(text: &str, settings: &OutputSettings, send_key: SendKey) -> Result<(), String> {
    let mut text = text.to_string();
    if settings.append_space && !text.ends_with(char::is_whitespace) {
        text.push(' ');
    }

    release_held_modifiers();

    if settings.method == PasteMethod::Type {
        std::thread::sleep(PRE_PASTE_DELAY);
        if !type_text(&text) {
            return Err(
                "Windows blocked simulated typing (is the target app running as administrator?)"
                    .into(),
            );
        }
        if send_key != SendKey::None {
            std::thread::sleep(Duration::from_millis(80));
            press_send_key(send_key);
        }
        return Ok(());
    }

    let snapshot = settings.restore_clipboard.then(Snapshot::capture);
    let seq = clipboard::set_text(&text, settings.restore_clipboard)?;
    std::thread::sleep(PRE_PASTE_DELAY);

    let posted = match settings.method {
        PasteMethod::ShiftInsert => chord(VK_SHIFT, VK_INSERT),
        _ => chord(VK_CONTROL, VK_V),
    };

    if posted && send_key != SendKey::None {
        std::thread::sleep(Duration::from_millis(150));
        press_send_key(send_key);
    }

    if let Some(snapshot) = snapshot {
        let delay =
            Duration::from_millis(settings.clipboard_restore_delay_ms).max(MIN_RESTORE_DELAY);
        std::thread::sleep(delay);
        // Only restore if nobody (user or app) changed the clipboard since our paste.
        if clipboard::sequence_number() == seq {
            if let Err(e) = snapshot.restore() {
                log::warn!("clipboard restore failed: {e}");
            }
        }
    }

    if !posted {
        return Err("Windows blocked the paste keystroke (is the target app running as administrator?). The text is on the clipboard.".into());
    }
    Ok(())
}

/// Copies the current selection of the focused app via Ctrl+C and returns it,
/// restoring the previous clipboard (used for the "selected text" context).
pub fn copy_selection() -> Option<String> {
    let snapshot = Snapshot::capture();
    let before = clipboard::sequence_number();
    // A held Shift/Alt from a shortcut like Ctrl+Shift+Space would turn Ctrl+C
    // into a different command (e.g. Ctrl+Shift+C opens DevTools in browsers).
    release_held_modifiers();
    // Always send a complete Ctrl+C chord. Relying on a physically held Ctrl
    // races with the user releasing the shortcut, and a bare "c" would then
    // overwrite the selection.
    chord(VK_CONTROL, VK_C);

    let deadline = std::time::Instant::now() + Duration::from_millis(250);
    while clipboard::sequence_number() == before && std::time::Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(10));
    }
    if clipboard::sequence_number() == before {
        return None; // Nothing selected (or the app ignored Ctrl+C).
    }
    let selected = clipboard::get_text();
    // Restores the previous contents (or emptiness) of the clipboard.
    let _ = snapshot.restore();
    selected.filter(|s| !s.trim().is_empty())
}
