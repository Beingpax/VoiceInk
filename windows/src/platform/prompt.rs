//! A minimal modal text-input dialog (used to enter API keys from the tray menu).

use super::wide;
use std::cell::RefCell;
use windows::core::{w, PCWSTR};
use windows::Win32::Foundation::{HWND, LPARAM, LRESULT, WPARAM};
use windows::Win32::Graphics::Gdi::{GetStockObject, COLOR_WINDOW, DEFAULT_GUI_FONT, HBRUSH};
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::UI::Input::KeyboardAndMouse::{EnableWindow, SetFocus};
use windows::Win32::UI::WindowsAndMessaging::{
    CreateWindowExW, DefWindowProcW, DestroyWindow, DispatchMessageW, GetMessageW,
    GetSystemMetrics, GetWindowTextLengthW, GetWindowTextW, IsDialogMessageW, IsWindow,
    RegisterClassW, SendMessageW, SetForegroundWindow, TranslateMessage, HMENU, IDCANCEL, IDOK,
    MSG, SM_CXSCREEN, SM_CYSCREEN, WINDOW_STYLE, WM_CLOSE, WM_COMMAND, WM_SETFONT, WNDCLASSW,
    WS_BORDER, WS_CAPTION, WS_CHILD, WS_EX_DLGMODALFRAME, WS_EX_TOPMOST, WS_SYSMENU, WS_TABSTOP,
    WS_VISIBLE,
};

const ES_PASSWORD: u32 = 0x0020;
const ES_AUTOHSCROLL: u32 = 0x0080;
const BS_DEFPUSHBUTTON: u32 = 0x0001;
const ID_EDIT: usize = 100;

thread_local! {
    static RESULT: RefCell<Option<Option<String>>> = const { RefCell::new(None) };
    static EDIT: RefCell<HWND> = RefCell::new(HWND::default());
}

unsafe extern "system" fn wnd_proc(
    hwnd: HWND,
    msg: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    match msg {
        WM_COMMAND => {
            let id = (wparam.0 & 0xFFFF) as i32;
            if id == IDOK.0 {
                let edit = EDIT.with(|e| *e.borrow());
                let len = GetWindowTextLengthW(edit);
                let mut buf = vec![0u16; len as usize + 1];
                let n = GetWindowTextW(edit, &mut buf);
                let text = String::from_utf16_lossy(&buf[..n.max(0) as usize]);
                RESULT.with(|r| *r.borrow_mut() = Some(Some(text)));
                let _ = DestroyWindow(hwnd);
            } else if id == IDCANCEL.0 {
                RESULT.with(|r| *r.borrow_mut() = Some(None));
                let _ = DestroyWindow(hwnd);
            }
            LRESULT(0)
        }
        WM_CLOSE => {
            RESULT.with(|r| *r.borrow_mut() = Some(None));
            let _ = DestroyWindow(hwnd);
            LRESULT(0)
        }
        _ => DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}

/// Shows a modal prompt and returns the entered text (`None` when cancelled).
/// `secret` masks the input. Runs a nested message loop on the UI thread.
pub fn ask(owner: HWND, title: &str, message: &str, secret: bool) -> Option<String> {
    RESULT.with(|r| *r.borrow_mut() = None);
    unsafe {
        let instance = GetModuleHandleW(None).ok()?;
        let class = w!("VoiceInkPrompt");
        let wc = WNDCLASSW {
            lpfnWndProc: Some(wnd_proc),
            hInstance: instance.into(),
            lpszClassName: class,
            hbrBackground: HBRUSH((COLOR_WINDOW.0 + 1) as isize as *mut _),
            ..Default::default()
        };
        RegisterClassW(&wc);

        let (w_, h_) = (440, 170);
        let x = (GetSystemMetrics(SM_CXSCREEN) - w_) / 2;
        let y = (GetSystemMetrics(SM_CYSCREEN) - h_) / 2;
        let title_w = wide(title);
        let dialog = CreateWindowExW(
            WS_EX_DLGMODALFRAME | WS_EX_TOPMOST,
            class,
            PCWSTR(title_w.as_ptr()),
            WS_CAPTION | WS_SYSMENU | WS_VISIBLE,
            x,
            y,
            w_,
            h_,
            Some(owner),
            None,
            Some(instance.into()),
            None,
        )
        .ok()?;

        let font = GetStockObject(DEFAULT_GUI_FONT);
        let child =
            |class: PCWSTR, text: &str, style: u32, x: i32, y: i32, w: i32, h: i32, id: usize| {
                let t = wide(text);
                let hwnd = CreateWindowExW(
                    Default::default(),
                    class,
                    PCWSTR(t.as_ptr()),
                    WS_CHILD | WS_VISIBLE | WINDOW_STYLE(style),
                    x,
                    y,
                    w,
                    h,
                    Some(dialog),
                    Some(HMENU(id as *mut _)),
                    Some(instance.into()),
                    None,
                )
                .unwrap_or_default();
                SendMessageW(
                    hwnd,
                    WM_SETFONT,
                    Some(WPARAM(font.0 as usize)),
                    Some(LPARAM(1)),
                );
                hwnd
            };

        child(w!("STATIC"), message, 0, 14, 12, 400, 36, 0);
        let mut edit_style = WS_BORDER.0 | WS_TABSTOP.0 | ES_AUTOHSCROLL;
        if secret {
            edit_style |= ES_PASSWORD;
        }
        let edit = child(w!("EDIT"), "", edit_style, 14, 52, 400, 24, ID_EDIT);
        EDIT.with(|e| *e.borrow_mut() = edit);
        child(
            w!("BUTTON"),
            "Save",
            WS_TABSTOP.0 | BS_DEFPUSHBUTTON,
            238,
            90,
            84,
            28,
            IDOK.0 as usize,
        );
        child(
            w!("BUTTON"),
            "Cancel",
            WS_TABSTOP.0,
            330,
            90,
            84,
            28,
            IDCANCEL.0 as usize,
        );

        if !owner.is_invalid() {
            let _ = EnableWindow(owner, false);
        }
        let _ = SetForegroundWindow(dialog);
        let _ = SetFocus(Some(edit));

        let mut msg = MSG::default();
        while RESULT.with(|r| r.borrow().is_none()) && IsWindow(Some(dialog)).as_bool() {
            if !GetMessageW(&mut msg, None, 0, 0).as_bool() {
                break;
            }
            // Gives Tab / Enter (IDOK) / Esc (IDCANCEL) dialog semantics.
            if !IsDialogMessageW(dialog, &msg).as_bool() {
                let _ = TranslateMessage(&msg);
                DispatchMessageW(&msg);
            }
        }
        if !owner.is_invalid() {
            let _ = EnableWindow(owner, true);
        }
    }
    RESULT.with(|r| r.borrow_mut().take()).flatten()
}
