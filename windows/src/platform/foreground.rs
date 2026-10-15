//! Foreground window information used for Modes, window context and paste targets.

use crate::modes::ForegroundInfo;
use std::time::Duration;
use windows::Win32::Foundation::{CloseHandle, HANDLE, HWND};
use windows::Win32::System::Threading::{
    GetCurrentProcessId, OpenProcess, PROCESS_NAME_WIN32, PROCESS_QUERY_LIMITED_INFORMATION, QueryFullProcessImageNameW,
};
use windows::Win32::UI::WindowsAndMessaging::{
    GetClassNameW, GetForegroundWindow, GetWindowTextLengthW, GetWindowTextW, GetWindowThreadProcessId, IsWindow,
    SetForegroundWindow,
};
use windows::core::PWSTR;

/// Window classes of the taskbar and notification-area overflow.
const SHELL_CLASSES: [&str; 4] =
    ["Shell_TrayWnd", "Shell_SecondaryTrayWnd", "NotifyIconOverflowWindow", "TopLevelWindowForOverflowXamlIsland"];
/// Gives the re-activated window time to accept input.
const FOCUS_SETTLE_DELAY: Duration = Duration::from_millis(50);
const MAX_PATH_CHARS: usize = 1024;

/// A process handle, closed on drop.
struct ProcessHandle(HANDLE);

impl Drop for ProcessHandle {
    fn drop(&mut self) {
        // SAFETY: the handle came from OpenProcess and is closed exactly once.
        let _ = unsafe { CloseHandle(self.0) };
    }
}

pub fn window_title(hwnd: HWND) -> String {
    // SAFETY: querying text of an arbitrary window handle is safe; invalid
    // handles yield 0. The buffer is sized from GetWindowTextLengthW.
    unsafe {
        let len = usize::try_from(GetWindowTextLengthW(hwnd)).unwrap_or(0);
        if len == 0 {
            return String::new();
        }
        let mut buf = vec![0u16; len + 1];
        let copied = usize::try_from(GetWindowTextW(hwnd, &mut buf)).unwrap_or(0);
        String::from_utf16_lossy(&buf[..copied])
    }
}

fn process_id(hwnd: HWND) -> u32 {
    let mut pid = 0u32;
    // SAFETY: `pid` is a valid out-parameter.
    unsafe { GetWindowThreadProcessId(hwnd, Some(&raw mut pid)) };
    pid
}

/// Lower-case executable name of the window's process, e.g. `slack.exe`.
pub fn process_name(hwnd: HWND) -> String {
    let pid = process_id(hwnd);
    if pid == 0 {
        return String::new();
    }
    // SAFETY: opening with the minimal query right; the handle is owned by the guard.
    let Ok(process) = (unsafe { OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid) }).map(ProcessHandle) else {
        return String::new();
    };
    let mut buf = [0u16; MAX_PATH_CHARS];
    let mut len = buf.len() as u32;
    // SAFETY: `buf` holds `len` characters; Windows writes the actual length back.
    let ok =
        unsafe { QueryFullProcessImageNameW(process.0, PROCESS_NAME_WIN32, PWSTR(buf.as_mut_ptr()), &raw mut len) };
    if ok.is_err() {
        return String::new();
    }
    let path = String::from_utf16_lossy(&buf[..len as usize]);
    path.rsplit(['\\', '/']).next().unwrap_or_default().to_lowercase()
}

fn class_name(hwnd: HWND) -> String {
    let mut buf = [0u16; 64];
    // SAFETY: `buf` is a valid output buffer.
    let len = usize::try_from(unsafe { GetClassNameW(hwnd, &mut buf) }).unwrap_or(0);
    String::from_utf16_lossy(&buf[..len])
}

/// True for `VoiceInk`'s own windows, the taskbar and invalid handles — windows
/// that must never become a paste target.
pub fn is_own_or_shell(hwnd: HWND) -> bool {
    // SAFETY: no preconditions.
    let own_pid = unsafe { GetCurrentProcessId() };
    hwnd.is_invalid() || process_id(hwnd) == own_pid || SHELL_CLASSES.contains(&class_name(hwnd).as_str())
}

/// Snapshot of the focused window.
pub fn current() -> (HWND, ForegroundInfo) {
    // SAFETY: no preconditions.
    let hwnd = unsafe { GetForegroundWindow() };
    if hwnd.is_invalid() {
        return (hwnd, ForegroundInfo::default());
    }
    (hwnd, ForegroundInfo { process_name: process_name(hwnd), window_title: window_title(hwnd) })
}

/// Re-focuses the window that was active when recording started, if focus moved.
pub fn restore_focus(hwnd: HWND) {
    // SAFETY: the handle is validated with IsWindow before use.
    unsafe {
        if hwnd.is_invalid() || !IsWindow(Some(hwnd)).as_bool() || GetForegroundWindow() == hwnd {
            return;
        }
        let _ = SetForegroundWindow(hwnd);
    }
    std::thread::sleep(FOCUS_SETTLE_DELAY);
}
