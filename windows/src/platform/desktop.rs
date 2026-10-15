//! Windows implementations of the UI's [`Desktop`] and [`Host`] services.

use super::{capture, clipboard, open_path};
use crate::ui::{Desktop, Host, UiHandle};
use std::path::Path;
use windows::Win32::Foundation::{HWND, LPARAM, WPARAM};
use windows::Win32::UI::WindowsAndMessaging::{DestroyWindow, PostMessageW, WM_APP};

/// Posted to the app window after the settings window saved `config.json`.
pub const WM_SETTINGS_SAVED: u32 = WM_APP + 8;

/// Microphones, clipboard and shell for the settings pages.
#[derive(Debug, Default, Clone, Copy)]
pub struct WindowsDesktop;

impl Desktop for WindowsDesktop {
    fn input_devices(&self) -> Vec<String> {
        capture::list_input_devices()
            .map(|devices| devices.into_iter().map(|(name, _)| name).collect())
            .unwrap_or_default()
    }

    fn copy_text(&self, text: &str) -> Result<(), String> {
        clipboard::set_text(text, false).map(drop).map_err(|e| e.to_string())
    }

    fn open_path(&self, path: &Path) {
        open_path(path);
    }

    /// Segoe UI, or the embedded Fira Sans where it is not installed
    /// (Windows Server Core, Wine).
    fn font_family(&self) -> Option<&'static str> {
        let windows_dir = std::env::var_os("WINDIR").unwrap_or_else(|| "C:\\Windows".into());
        let segoe = Path::new(&windows_dir).join("Fonts").join("segoeui.ttf");
        Some(if segoe.exists() { "Segoe UI" } else { "Fira Sans" })
    }
}

/// Connects the UI to the tray app's window.
pub struct TrayHost {
    /// The app window (owner of the tray icon, hooks and overlay).
    pub window: HWND,
    /// Hands the [`UiHandle`] to the app once the UI is running.
    pub on_connected: Box<dyn Fn(UiHandle)>,
}

impl Host for TrayHost {
    fn connected(&self, handle: UiHandle) {
        (self.on_connected)(handle);
    }

    fn settings_saved(&self) {
        // Posted rather than called: the app reloads on its own message.
        // SAFETY: posting to our own window from its thread.
        let _ = unsafe { PostMessageW(Some(self.window), WM_SETTINGS_SAVED, WPARAM(0), LPARAM(0)) };
    }

    fn quit(&self) {
        // SAFETY: our own window; WM_DESTROY releases hooks, tray and app.
        let _ = unsafe { DestroyWindow(self.window) };
    }
}
