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

pub mod app;
pub mod autostart;
pub mod capture;
pub mod clipboard;
pub mod foreground;
pub mod hotkey;
pub mod icon;
pub mod overlay;
pub mod paste;
pub mod prompt;
pub mod settings;
pub mod sound;
pub mod tray;
pub mod volume;

use windows::core::PCWSTR;
use windows::Win32::System::Console::{AttachConsole, ATTACH_PARENT_PROCESS};
use windows::Win32::UI::WindowsAndMessaging::{MessageBoxW, MB_ICONERROR, MB_OK};

/// NUL-terminated UTF-16 buffer for Win32 string parameters.
pub fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

/// Copies `s` into a fixed-size UTF-16 array (truncating), e.g. `NOTIFYICONDATAW::szTip`.
pub fn fill_wide<const N: usize>(dst: &mut [u16; N], s: &str) {
    let mut i = 0;
    for unit in s.encode_utf16() {
        if i + 1 >= N {
            break;
        }
        dst[i] = unit;
        i += 1;
    }
    dst[i] = 0;
}

/// Lets CLI subcommands print to the console that launched the (GUI-subsystem) exe.
pub fn attach_parent_console() {
    unsafe {
        let _ = AttachConsole(ATTACH_PARENT_PROCESS);
    }
}

pub fn show_error(message: &str) {
    let text = wide(message);
    let title = wide("VoiceInk");
    unsafe {
        MessageBoxW(
            None,
            PCWSTR(text.as_ptr()),
            PCWSTR(title.as_ptr()),
            MB_OK | MB_ICONERROR,
        );
    }
}
