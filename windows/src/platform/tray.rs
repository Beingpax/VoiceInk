//! Notification-area icon and its context menu (the macOS menu-bar extra).

use super::icon::{create_icon, IconState};
use super::{fill_wide, wide};
use windows::core::PCWSTR;
use windows::Win32::Foundation::{HWND, POINT};
use windows::Win32::UI::Shell::{
    Shell_NotifyIconW, NIF_ICON, NIF_INFO, NIF_MESSAGE, NIF_TIP, NIIF_ERROR, NIIF_INFO,
    NIIF_WARNING, NIM_ADD, NIM_DELETE, NIM_MODIFY, NIM_SETVERSION, NOTIFYICONDATAW,
    NOTIFYICONDATAW_0, NOTIFYICON_VERSION_4, NOTIFY_ICON_INFOTIP_FLAGS,
};
use windows::Win32::UI::WindowsAndMessaging::{
    AppendMenuW, CreatePopupMenu, DestroyIcon, DestroyMenu, GetCursorPos, PostMessageW,
    SetForegroundWindow, TrackPopupMenu, HICON, HMENU, MENU_ITEM_FLAGS, MF_CHECKED, MF_GRAYED,
    MF_POPUP, MF_SEPARATOR, MF_STRING, TPM_BOTTOMALIGN, TPM_RETURNCMD, TPM_RIGHTBUTTON, WM_APP,
    WM_NULL,
};

/// Tray callback message; with `NOTIFYICON_VERSION_4` the event is `LOWORD(lParam)`.
pub const WM_TRAY: u32 = WM_APP + 4;
const TRAY_ID: u32 = 1;

#[derive(Debug, Clone, Copy)]
pub enum NoticeKind {
    Info,
    Warning,
    Error,
}

pub struct Tray {
    hwnd: HWND,
    icons: [HICON; 3],
    added: bool,
}

impl Tray {
    pub fn new(hwnd: HWND) -> Tray {
        let make = |s| create_icon(32, s).unwrap_or_default();
        Tray {
            hwnd,
            icons: [
                make(IconState::Idle),
                make(IconState::Recording),
                make(IconState::Busy),
            ],
            added: false,
        }
    }

    fn icon_for(&self, state: IconState) -> HICON {
        match state {
            IconState::Idle => self.icons[0],
            IconState::Recording => self.icons[1],
            IconState::Busy => self.icons[2],
        }
    }

    fn base(&self) -> NOTIFYICONDATAW {
        NOTIFYICONDATAW {
            cbSize: std::mem::size_of::<NOTIFYICONDATAW>() as u32,
            hWnd: self.hwnd,
            uID: TRAY_ID,
            ..Default::default()
        }
    }

    /// Adds the icon (also used to re-add it after Explorer restarts).
    pub fn add(&mut self, tip: &str) {
        let mut data = self.base();
        data.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
        data.uCallbackMessage = WM_TRAY;
        data.hIcon = self.icon_for(IconState::Idle);
        fill_wide(&mut data.szTip, tip);
        unsafe {
            self.added = Shell_NotifyIconW(NIM_ADD, &data).as_bool();
            data.Anonymous = NOTIFYICONDATAW_0 {
                uVersion: NOTIFYICON_VERSION_4,
            };
            let _ = Shell_NotifyIconW(NIM_SETVERSION, &data);
        }
    }

    pub fn set_state(&self, state: IconState, tip: &str) {
        let mut data = self.base();
        data.uFlags = NIF_ICON | NIF_TIP;
        data.hIcon = self.icon_for(state);
        fill_wide(&mut data.szTip, tip);
        unsafe {
            let _ = Shell_NotifyIconW(NIM_MODIFY, &data);
        }
    }

    /// Shows a toast/balloon notification attached to the tray icon.
    pub fn notify(&self, title: &str, message: &str, kind: NoticeKind) {
        let mut data = self.base();
        data.uFlags = NIF_INFO;
        fill_wide(&mut data.szInfoTitle, title);
        fill_wide(&mut data.szInfo, message);
        data.dwInfoFlags = match kind {
            NoticeKind::Info => NIIF_INFO,
            NoticeKind::Warning => NIIF_WARNING,
            NoticeKind::Error => NIIF_ERROR,
        } | NOTIFY_ICON_INFOTIP_FLAGS(0);
        unsafe {
            let _ = Shell_NotifyIconW(NIM_MODIFY, &data);
        }
    }

    pub fn remove(&mut self) {
        if self.added {
            unsafe {
                let _ = Shell_NotifyIconW(NIM_DELETE, &self.base());
            }
            self.added = false;
        }
    }
}

impl Drop for Tray {
    fn drop(&mut self) {
        self.remove();
        for icon in self.icons {
            if !icon.is_invalid() {
                unsafe {
                    let _ = DestroyIcon(icon);
                }
            }
        }
    }
}

/// Thin builder over Win32 popup menus.
pub struct Menu {
    handle: HMENU,
}

impl Menu {
    pub fn new() -> Menu {
        Menu {
            handle: unsafe { CreatePopupMenu().unwrap_or_default() },
        }
    }

    fn append(&self, flags: MENU_ITEM_FLAGS, id: usize, text: &str) {
        let w = wide(text);
        unsafe {
            let _ = AppendMenuW(self.handle, flags, id, PCWSTR(w.as_ptr()));
        }
    }

    pub fn item(&self, id: usize, text: &str) -> &Self {
        self.append(MF_STRING, id, text);
        self
    }

    pub fn check(&self, id: usize, text: &str, checked: bool) -> &Self {
        self.append(
            if checked {
                MF_STRING | MF_CHECKED
            } else {
                MF_STRING
            },
            id,
            text,
        );
        self
    }

    pub fn disabled(&self, text: &str) -> &Self {
        self.append(MF_STRING | MF_GRAYED, 0, text);
        self
    }

    pub fn separator(&self) -> &Self {
        unsafe {
            let _ = AppendMenuW(self.handle, MF_SEPARATOR, 0, PCWSTR::null());
        }
        self
    }

    /// Appends `sub` as a submenu; ownership moves to this menu.
    pub fn submenu(&self, text: &str, sub: Menu) -> &Self {
        let handle = sub.handle;
        std::mem::forget(sub);
        self.append(MF_STRING | MF_POPUP, handle.0 as usize, text);
        self
    }

    /// Shows the menu at the cursor and returns the chosen command id (0 = none).
    pub fn track(&self, owner: HWND) -> usize {
        unsafe {
            let mut pt = POINT::default();
            let _ = GetCursorPos(&mut pt);
            // Required so the menu closes when the user clicks elsewhere.
            let _ = SetForegroundWindow(owner);
            let cmd = TrackPopupMenu(
                self.handle,
                TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_BOTTOMALIGN,
                pt.x,
                pt.y,
                None,
                owner,
                None,
            );
            let _ = PostMessageW(Some(owner), WM_NULL, Default::default(), Default::default());
            cmd.0 as usize
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
        unsafe {
            let _ = DestroyMenu(self.handle);
        }
    }
}
