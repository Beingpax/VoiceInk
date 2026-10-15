//! The Dashboard & Settings window, built with [iced](https://iced.rs).
//!
//! The UI is portable: it depends only on the core ([`AppContext`],
//! [`Config`](crate::config::Config), history, secrets) plus two small
//! traits the host implements:
//!
//! * [`Desktop`] — operating-system services the pages use (microphones,
//!   clipboard, opening files).
//! * [`Host`] — what the surrounding application does when the UI saves
//!   settings or the user quits.
//!
//! [`run`] starts iced as a *daemon*: it owns the main-thread event loop for
//! the whole process but only shows a window when asked through a
//! [`UiHandle`]. On Windows the tray icon, keyboard hooks and recorder
//! overlay live on the same thread, so their window messages are pumped by
//! iced's loop.

mod daemon;
mod settings;
mod style;

pub use daemon::{Launch, UiHandle, UiRequest, run};

use std::path::Path;

/// Operating-system services used by the settings pages.
pub trait Desktop {
    /// Friendly names of the available microphones.
    fn input_devices(&self) -> Vec<String> {
        Vec::new()
    }

    /// Puts `text` on the clipboard.
    ///
    /// # Errors
    /// Returns a user-facing message when the clipboard is unavailable.
    fn copy_text(&self, text: &str) -> Result<(), String>;

    /// Opens a file or folder with its default application.
    fn open_path(&self, path: &Path);

    /// The font family for the UI; `None` uses the system default.
    fn font_family(&self) -> Option<&'static str> {
        None
    }
}

/// What the application around the UI does on its behalf.
pub trait Host {
    /// The UI is ready to receive requests through `handle`.
    fn connected(&self, _handle: UiHandle) {}

    /// The settings file and API keys were written.
    fn settings_saved(&self) {}

    /// The user quit; release OS resources before the event loop ends.
    fn quit(&self) {}
}

/// A [`Desktop`] for platforms without native integration: clipboard and
/// file opening report that they are unavailable.
#[derive(Debug, Default, Clone, Copy)]
pub struct BasicDesktop;

impl Desktop for BasicDesktop {
    fn copy_text(&self, _text: &str) -> Result<(), String> {
        Err("The clipboard is not available on this platform".into())
    }

    fn open_path(&self, path: &Path) {
        log::info!("open {}", path.display());
    }
}

/// A [`Host`] that needs no notifications (standalone settings window).
#[derive(Debug, Default, Clone, Copy)]
pub struct NoHost;

impl Host for NoHost {}
