//! Notification-area icon and popup menus (the macOS menu-bar extra).

use super::icon::{IconState, OwnedIcon, create_icon};
use super::{fill_wide, wide};
use windows::Win32::Foundation::{HWND, LPARAM, POINT, WPARAM};
use windows::Win32::UI::Shell::{
    NIF_ICON, NIF_INFO, NIF_MESSAGE, NIF_TIP, NIIF_ERROR, NIIF_INFO, NIIF_WARNING, NIM_ADD, NIM_DELETE, NIM_MODIFY,
    NIM_SETVERSION, NOTIFYICON_VERSION_4, NOTIFYICONDATAW, NOTIFYICONDATAW_0, Shell_NotifyIconW,
};
use windows::Win32::UI::WindowsAndMessaging::{
    AppendMenuW, CreatePopupMenu, DestroyMenu, GetCursorPos, HICON, HMENU, MENU_ITEM_FLAGS, MF_CHECKED, MF_GRAYED,
    MF_POPUP, MF_SEPARATOR, MF_STRING, PostMessageW, SetForegroundWindow, TPM_BOTTOMALIGN, TPM_RETURNCMD,
    TPM_RIGHTBUTTON, TrackPopupMenu, WM_APP, WM_NULL,
};
use windows::core::PCWSTR;

/// Tray callback message; with `NOTIFYICON_VERSION_4` the event is `LOWORD(lParam)`.
pub const WM_TRAY: u32 = WM_APP + 4;
/// `NOTIFYICON_VERSION_4` events for a left click / keyboard selection.
pub const NIN_SELECT: u32 = 0x400;
pub const NIN_KEYSELECT: u32 = 0x401;

const TRAY_ID: u32 = 1;
const TRAY_ICON_SIZE: usize = 32;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NoticeKind {
    Info,
    Warning,
    Error,
}

pub struct Tray {
    hwnd: HWND,
    idle: Option<OwnedIcon>,
    recording: Option<OwnedIcon>,
    busy: Option<OwnedIcon>,
    added: bool,
}

impl Tray {
    pub fn new(hwnd: HWND) -> Tray {
        Tray {
            hwnd,
            idle: create_icon(TRAY_ICON_SIZE, IconState::Idle),
            recording: create_icon(TRAY_ICON_SIZE, IconState::Recording),
            busy: create_icon(TRAY_ICON_SIZE, IconState::Busy),
            added: false,
        }
    }

    fn icon_for(&self, state: IconState) -> HICON {
        let icon = match state {
            IconState::Idle => &self.idle,
            IconState::Recording => &self.recording,
            IconState::Busy => &self.busy,
        };
        icon.as_ref().map(OwnedIcon::handle).unwrap_or_default()
    }

    fn data(&self) -> NOTIFYICONDATAW {
        NOTIFYICONDATAW {
            cbSize: size_of::<NOTIFYICONDATAW>() as u32,
            hWnd: self.hwnd,
            uID: TRAY_ID,
            ..Default::default()
        }
    }

    fn shell(message: windows::Win32::UI::Shell::NOTIFY_ICON_MESSAGE, data: &NOTIFYICONDATAW) -> bool {
        // SAFETY: `data` is a fully initialized NOTIFYICONDATAW with a correct cbSize.
        unsafe { Shell_NotifyIconW(message, data) }.as_bool()
    }

    /// Adds the icon (also used to re-add it after Explorer restarts).
    pub fn add(&mut self, tip: &str) {
        let mut data = self.data();
        data.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
        data.uCallbackMessage = WM_TRAY;
        data.hIcon = self.icon_for(IconState::Idle);
        fill_wide(&mut data.szTip, tip);
        self.added = Self::shell(NIM_ADD, &data);
        data.Anonymous = NOTIFYICONDATAW_0 { uVersion: NOTIFYICON_VERSION_4 };
        Self::shell(NIM_SETVERSION, &data);
    }

    pub fn set_state(&self, state: IconState, tip: &str) {
        let mut data = self.data();
        data.uFlags = NIF_ICON | NIF_TIP;
        data.hIcon = self.icon_for(state);
        fill_wide(&mut data.szTip, tip);
        Self::shell(NIM_MODIFY, &data);
    }

    /// Shows a toast/balloon notification attached to the tray icon.
    pub fn notify(&self, title: &str, message: &str, kind: NoticeKind) {
        let mut data = self.data();
        data.uFlags = NIF_INFO;
        fill_wide(&mut data.szInfoTitle, title);
        fill_wide(&mut data.szInfo, message);
        data.dwInfoFlags = match kind {
            NoticeKind::Info => NIIF_INFO,
            NoticeKind::Warning => NIIF_WARNING,
            NoticeKind::Error => NIIF_ERROR,
        };
        Self::shell(NIM_MODIFY, &data);
    }

    pub fn remove(&mut self) {
        if std::mem::take(&mut self.added) {
            Self::shell(NIM_DELETE, &self.data());
        }
    }
}

impl Drop for Tray {
    fn drop(&mut self) {
        self.remove();
    }
}

/// Thin builder over Win32 popup menus; item ids are chosen by the caller.
pub struct Menu {
    handle: HMENU,
}

impl Menu {
    pub fn new() -> Menu {
        // SAFETY: no preconditions; a failed creation yields a null menu that
        // AppendMenuW and TrackPopupMenu reject harmlessly.
        Menu { handle: unsafe { CreatePopupMenu() }.unwrap_or_default() }
    }

    fn append(&self, flags: MENU_ITEM_FLAGS, id: usize, text: &str) {
        let text = wide(text);
        // SAFETY: `text` is NUL-terminated and outlives the call (the menu copies it).
        let _ = unsafe { AppendMenuW(self.handle, flags, id, PCWSTR(text.as_ptr())) };
    }

    pub fn item(&self, id: usize, text: &str) -> &Self {
        self.append(MF_STRING, id, text);
        self
    }

    pub fn check(&self, id: usize, text: &str, checked: bool) -> &Self {
        self.append(if checked { MF_STRING | MF_CHECKED } else { MF_STRING }, id, text);
        self
    }

    pub fn disabled(&self, text: &str) -> &Self {
        self.append(MF_STRING | MF_GRAYED, 0, text);
        self
    }

    pub fn separator(&self) -> &Self {
        // SAFETY: separators take no string.
        let _ = unsafe { AppendMenuW(self.handle, MF_SEPARATOR, 0, PCWSTR::null()) };
        self
    }

    /// Appends `sub` as a submenu; this menu takes ownership of it.
    pub fn submenu(&self, text: &str, sub: Menu) -> &Self {
        let handle = std::mem::ManuallyDrop::new(sub).handle;
        self.append(MF_STRING | MF_POPUP, handle.0 as usize, text);
        self
    }

    /// Shows the menu at the cursor and returns the chosen id (0 = none).
    pub fn track(&self, owner: HWND) -> usize {
        let mut cursor = POINT::default();
        // SAFETY: valid out-parameter, menu and owner window. The foreground
        // switch is required so the menu closes when the user clicks elsewhere;
        // the WM_NULL afterwards is the documented workaround for a second click.
        unsafe {
            let _ = GetCursorPos(&raw mut cursor);
            let _ = SetForegroundWindow(owner);
            let chosen = TrackPopupMenu(
                self.handle,
                TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_BOTTOMALIGN,
                cursor.x,
                cursor.y,
                None,
                owner,
                None,
            );
            let _ = PostMessageW(Some(owner), WM_NULL, WPARAM::default(), LPARAM::default());
            usize::try_from(chosen.0).unwrap_or(0)
        }
    }
}

impl Default for Menu {
    fn default() -> Self {
        Self::new()
    }
}

impl Drop for Menu {
    fn drop(&mut self) {
        // SAFETY: destroys this menu and its submenus exactly once.
        let _ = unsafe { DestroyMenu(self.handle) };
    }
}
