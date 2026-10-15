//! Win32 integration built on the `windows` crate.
//!
//! | macOS (Swift)                         | Windows (this module)                        |
//! |---------------------------------------|----------------------------------------------|
//! | `CoreAudioRecorder` (AUHAL)           | [`capture`] — WASAPI shared-mode capture     |
//! | `ShortcutMonitor` / CGEvent taps      | [`hotkey`] — `WH_KEYBOARD_LL`/`WH_MOUSE_LL`  |
//! | `CursorPaster` + `NSPasteboard`       | [`paste`], [`clipboard`] — `SendInput`       |
//! | `MenuBarManager`                      | [`tray`] — `Shell_NotifyIconW`               |
//! | Mini/Notch recorder panels            | [`overlay`] — non-activating layered window  |
//! | `SoundManager`                        | [`sound`] — `PlaySoundW`                     |
//! | `MediaController` (mute while recording) | [`volume`] — `IAudioEndpointVolume`       |
//! | Keychain                              | `crate::credentials` — DPAPI                 |
//! | `NSWorkspace.frontmostApplication`    | [`foreground`]                               |

// Win32 APIs take i32/u32 pixel and size values everywhere; the casts in
// this layer convert between those and Rust's usize/f32 deliberately.
#![allow(
    clippy::cast_possible_truncation,
    clippy::cast_possible_wrap,
    clippy::cast_sign_loss,
    clippy::cast_precision_loss
)]

pub mod actions;
pub mod app;
pub mod autostart;
pub mod capture;
pub mod clipboard;
mod com;
pub mod error;
pub mod foreground;
mod gdi;
pub mod hotkey;
pub mod icon;
pub mod overlay;
pub mod paste;
pub mod settings;
pub mod sound;
pub mod tray;
pub mod volume;

pub use error::{Error, Result};

use std::path::Path;
use windows::Win32::System::Console::{ATTACH_PARENT_PROCESS, AttachConsole};
use windows::Win32::UI::Shell::ShellExecuteW;
use windows::Win32::UI::WindowsAndMessaging::{MB_ICONERROR, MB_OK, MessageBoxW, SW_SHOWNORMAL};
use windows::core::{PCWSTR, w};

/// NUL-terminated UTF-16 buffer for Win32 string parameters.
pub fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

/// Copies `s` into a fixed-size UTF-16 array (truncating, always
/// NUL-terminated), e.g. `NOTIFYICONDATAW::szTip`.
pub fn fill_wide<const N: usize>(dst: &mut [u16; N], s: &str) {
    let capacity = N.saturating_sub(1);
    let mut len = 0;
    for (slot, unit) in dst.iter_mut().zip(s.encode_utf16().take(capacity)) {
        *slot = unit;
        len += 1;
    }
    if let Some(end) = dst.get_mut(len) {
        *end = 0;
    }
}

/// Lets CLI subcommands print to the console that launched the (GUI-subsystem) exe.
pub fn attach_parent_console() {
    // SAFETY: no preconditions; failure (no parent console) is harmless.
    let _ = unsafe { AttachConsole(ATTACH_PARENT_PROCESS) };
}

/// Opens a file or folder with its default application.
pub fn open_path(path: &Path) {
    let path = wide(&path.to_string_lossy());
    // SAFETY: `path` is NUL-terminated and outlives the call.
    unsafe { ShellExecuteW(None, w!("open"), PCWSTR(path.as_ptr()), None, None, SW_SHOWNORMAL) };
}

pub fn show_error(message: &str) {
    let text = wide(message);
    // SAFETY: `text` is a NUL-terminated buffer that outlives the call.
    unsafe { MessageBoxW(None, PCWSTR(text.as_ptr()), w!("VoiceInk"), MB_OK | MB_ICONERROR) };
}
