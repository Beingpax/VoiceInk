//! The app's connection to the iced UI (see [`crate::ui`]).

use crate::settings_page::SettingsPage;
use crate::ui::{UiHandle, UiRequest};

/// Sends requests to the UI. Requests made before the UI has connected
/// (e.g. `voiceink dashboard` at startup) are delivered once it does.
#[derive(Debug, Default)]
pub struct UiLink {
    handle: Option<UiHandle>,
    pending: Vec<UiRequest>,
}

impl UiLink {
    pub fn connect(&mut self, handle: UiHandle) {
        for request in self.pending.drain(..) {
            handle.send(request);
        }
        self.handle = Some(handle);
    }

    fn send(&mut self, request: UiRequest) {
        match &self.handle {
            Some(handle) => handle.send(request),
            None => self.pending.push(request),
        }
    }

    pub fn open_settings(&mut self, page: SettingsPage) {
        self.send(UiRequest::OpenSettings(page));
    }

    pub fn history_changed(&mut self) {
        if self.handle.is_some() {
            self.send(UiRequest::HistoryChanged);
        }
    }

    /// Ends the event loop (the UI calls back to release the app first).
    pub fn quit(&mut self) {
        self.send(UiRequest::Quit);
    }
}
