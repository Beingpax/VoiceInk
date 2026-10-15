//! Messages from worker threads to the UI thread.
//!
//! Workers send a [`UiEvent`] through a channel and wake the window with
//! [`WM_UI_EVENT`]; the window drains the channel on the UI thread. This
//! replaces global mutex-protected queues.

use super::super::tray::NoticeKind;
use crate::pipeline::{PipelineOutput, Stage};
use std::sync::mpsc::{self, Receiver, Sender};
use windows::Win32::Foundation::{HWND, LPARAM, WPARAM};
use windows::Win32::UI::WindowsAndMessaging::{PostMessageW, WM_APP};

/// Posted to the app window whenever an event was queued.
pub const WM_UI_EVENT: u32 = WM_APP + 3;

/// Identifies one transcription job.
pub type JobId = u64;

#[derive(Debug)]
pub enum UiEvent {
    Stage { job: JobId, stage: Stage },
    Finished { job: JobId, output: Box<PipelineOutput> },
    Notice(Notice),
}

/// A tray notification.
#[derive(Debug, Clone)]
pub struct Notice {
    pub title: String,
    pub message: String,
    pub kind: NoticeKind,
}

impl Notice {
    pub fn new(title: impl Into<String>, message: impl Into<String>, kind: NoticeKind) -> Self {
        Self { title: title.into(), message: message.into(), kind }
    }
}

/// A window handle that may cross threads. Only used with `PostMessageW`,
/// which is safe to call from any thread.
#[derive(Debug, Clone, Copy)]
pub struct SendHwnd(isize);

impl SendHwnd {
    pub fn new(hwnd: HWND) -> Self {
        Self(hwnd.0 as isize)
    }

    pub fn get(self) -> HWND {
        HWND(self.0 as *mut _)
    }
}

/// Sending half, cloned into worker threads.
#[derive(Debug, Clone)]
pub struct UiSender {
    tx: Sender<UiEvent>,
    window: SendHwnd,
}

impl UiSender {
    pub fn send(&self, event: UiEvent) {
        if self.tx.send(event).is_ok() {
            // SAFETY: PostMessageW may be called from any thread; a destroyed
            // window just drops the message.
            let _ = unsafe { PostMessageW(Some(self.window.get()), WM_UI_EVENT, WPARAM(0), LPARAM(0)) };
        }
    }

    pub fn notice(&self, title: &str, message: &str, kind: NoticeKind) {
        self.send(UiEvent::Notice(Notice::new(title, message, kind)));
    }
}

/// Creates the channel for events addressed to `window`.
pub fn channel(window: HWND) -> (UiSender, Receiver<UiEvent>) {
    let (tx, rx) = mpsc::channel();
    (UiSender { tx, window: SendHwnd::new(window) }, rx)
}
