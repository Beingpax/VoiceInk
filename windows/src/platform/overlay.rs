//! The floating recorder pill (macOS mini/notch recorder).
//!
//! A topmost, non-activating layered window so the focused app keeps keyboard
//! focus — essential for pasting into it afterwards. Clicking it stops the
//! recording. Painted with GDI into an off-screen buffer.

use crate::config::OverlayPosition;
use std::cell::RefCell;
use std::collections::VecDeque;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::Arc;
use std::time::Instant;
use windows::core::w;
use windows::Win32::Foundation::{COLORREF, HWND, LPARAM, LRESULT, RECT, WPARAM};
use windows::Win32::Graphics::Gdi::{
    BeginPaint, BitBlt, CreateCompatibleBitmap, CreateCompatibleDC, CreateFontW,
    CreateRoundRectRgn, CreateSolidBrush, DeleteDC, DeleteObject, DrawTextW, EndPaint, FillRect,
    GetMonitorInfoW, GetStockObject, InvalidateRect, MonitorFromWindow, RoundRect, SelectObject,
    SetBkMode, SetTextColor, SetWindowRgn, CLEARTYPE_QUALITY, CLIP_DEFAULT_PRECIS, DEFAULT_CHARSET,
    DT_END_ELLIPSIS, DT_LEFT, DT_SINGLELINE, DT_VCENTER, FW_SEMIBOLD, HGDIOBJ, MONITORINFO,
    MONITOR_DEFAULTTOPRIMARY, NULL_PEN, OUT_DEFAULT_PRECIS, PAINTSTRUCT, SRCCOPY, TRANSPARENT,
};
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::UI::HiDpi::{GetDpiForMonitor, MDT_EFFECTIVE_DPI};
use windows::Win32::UI::WindowsAndMessaging::{
    CreateWindowExW, DefWindowProcW, GetForegroundWindow, KillTimer, LoadCursorW, PostMessageW,
    RegisterClassW, SetLayeredWindowAttributes, SetTimer, SetWindowPos, ShowWindow, CS_HREDRAW,
    CS_VREDRAW, HWND_TOPMOST, IDC_HAND, LWA_ALPHA, MA_NOACTIVATE, SWP_NOACTIVATE, SW_HIDE,
    SW_SHOWNOACTIVATE, WM_APP, WM_LBUTTONUP, WM_MOUSEACTIVATE, WM_PAINT, WM_TIMER, WNDCLASSW,
    WS_EX_LAYERED, WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW, WS_EX_TOPMOST, WS_POPUP,
};

/// Posted to the owner when the user clicks the overlay.
pub const WM_OVERLAY_CLICKED: u32 = WM_APP + 6;

const TIMER_ID: usize = 1;
const BASE_WIDTH: i32 = 236;
const BASE_HEIGHT: i32 = 44;
const BARS: usize = 14;

#[derive(Debug, Clone)]
pub enum View {
    Recording {
        started: Instant,
        level: Arc<AtomicU32>,
        mode: Option<String>,
    },
    Transcribing,
    Enhancing,
    Message {
        text: String,
        until: Instant,
    },
}

struct OverlayState {
    owner: HWND,
    view: Option<View>,
    history: VecDeque<f32>,
    scale: f32,
}

thread_local! {
    static STATE: RefCell<Option<OverlayState>> = const { RefCell::new(None) };
}

pub struct Overlay {
    hwnd: HWND,
    position: OverlayPosition,
}

fn rgb(r: u8, g: u8, b: u8) -> COLORREF {
    COLORREF(r as u32 | (g as u32) << 8 | (b as u32) << 16)
}

impl Overlay {
    pub fn create(owner: HWND, position: OverlayPosition) -> Result<Overlay, String> {
        unsafe {
            let instance = GetModuleHandleW(None).map_err(|e| e.to_string())?;
            let class = w!("VoiceInkRecorderOverlay");
            let wc = WNDCLASSW {
                style: CS_HREDRAW | CS_VREDRAW,
                lpfnWndProc: Some(wnd_proc),
                hInstance: instance.into(),
                lpszClassName: class,
                hCursor: LoadCursorW(None, IDC_HAND).unwrap_or_default(),
                ..Default::default()
            };
            RegisterClassW(&wc);
            let hwnd = CreateWindowExW(
                WS_EX_LAYERED | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST,
                class,
                w!("VoiceInk Recorder"),
                WS_POPUP,
                0,
                0,
                BASE_WIDTH,
                BASE_HEIGHT,
                None,
                None,
                Some(instance.into()),
                None,
            )
            .map_err(|e| format!("overlay window: {e}"))?;
            let _ = SetLayeredWindowAttributes(hwnd, COLORREF(0), 240, LWA_ALPHA);
            STATE.with(|s| {
                *s.borrow_mut() = Some(OverlayState {
                    owner,
                    view: None,
                    history: VecDeque::from(vec![0.0; BARS]),
                    scale: 1.0,
                })
            });
            Ok(Overlay { hwnd, position })
        }
    }

    pub fn set_position(&mut self, position: OverlayPosition) {
        self.position = position;
        if position == OverlayPosition::Hidden {
            self.hide();
        }
    }

    pub fn show(&self, view: View) {
        if self.position == OverlayPosition::Hidden {
            return;
        }
        STATE.with(|s| {
            if let Some(state) = s.borrow_mut().as_mut() {
                state.view = Some(view);
                state.history.iter_mut().for_each(|v| *v = 0.0);
            }
        });
        self.place();
        unsafe {
            let _ = ShowWindow(self.hwnd, SW_SHOWNOACTIVATE);
            SetTimer(Some(self.hwnd), TIMER_ID, 33, None);
            let _ = InvalidateRect(Some(self.hwnd), None, false);
        }
    }

    pub fn hide(&self) {
        STATE.with(|s| {
            if let Some(state) = s.borrow_mut().as_mut() {
                state.view = None;
            }
        });
        unsafe {
            let _ = KillTimer(Some(self.hwnd), TIMER_ID);
            let _ = ShowWindow(self.hwnd, SW_HIDE);
        }
    }

    /// Positions the pill on the monitor of the focused window, DPI-scaled.
    fn place(&self) {
        unsafe {
            let monitor = MonitorFromWindow(GetForegroundWindow(), MONITOR_DEFAULTTOPRIMARY);
            let mut info = MONITORINFO {
                cbSize: std::mem::size_of::<MONITORINFO>() as u32,
                ..Default::default()
            };
            if !GetMonitorInfoW(monitor, &mut info).as_bool() {
                return;
            }
            let (mut dx, mut dy) = (96u32, 96u32);
            let _ = GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, &mut dx, &mut dy);
            let scale = dx as f32 / 96.0;
            STATE.with(|s| {
                if let Some(state) = s.borrow_mut().as_mut() {
                    state.scale = scale;
                }
            });
            let width = (BASE_WIDTH as f32 * scale) as i32;
            let height = (BASE_HEIGHT as f32 * scale) as i32;
            let work = info.rcWork;
            let x = work.left + (work.right - work.left - width) / 2;
            let margin = (24.0 * scale) as i32;
            let y = match self.position {
                OverlayPosition::TopCenter => work.top + margin,
                _ => work.bottom - height - margin,
            };
            let _ = SetWindowPos(
                self.hwnd,
                Some(HWND_TOPMOST),
                x,
                y,
                width,
                height,
                SWP_NOACTIVATE,
            );
            let region = CreateRoundRectRgn(0, 0, width + 1, height + 1, height, height);
            SetWindowRgn(self.hwnd, Some(region), true);
        }
    }
}

impl Drop for Overlay {
    fn drop(&mut self) {
        self.hide();
    }
}

fn label(view: &View) -> (String, (u8, u8, u8)) {
    match view {
        View::Recording { started, mode, .. } => {
            let secs = started.elapsed().as_secs();
            let base = format!("{}:{:02}", secs / 60, secs % 60);
            let text = match mode {
                Some(m) => format!("{base}  ·  {m}"),
                None => base,
            };
            (text, (0xEF, 0x44, 0x44))
        }
        View::Transcribing => ("Transcribing…".into(), (0x3B, 0x82, 0xF6)),
        View::Enhancing => ("Enhancing…".into(), (0xA8, 0x55, 0xF7)),
        View::Message { text, .. } => (text.clone(), (0xF5, 0x9E, 0x0B)),
    }
}

unsafe fn paint(hwnd: HWND) {
    let mut ps = PAINTSTRUCT::default();
    let hdc = BeginPaint(hwnd, &mut ps);
    let mut rect = RECT::default();
    let _ = windows::Win32::UI::WindowsAndMessaging::GetClientRect(hwnd, &mut rect);
    let (w, h) = (rect.right - rect.left, rect.bottom - rect.top);

    let mem = CreateCompatibleDC(Some(hdc));
    let bmp = CreateCompatibleBitmap(hdc, w, h);
    let old_bmp = SelectObject(mem, HGDIOBJ(bmp.0));

    let bg = CreateSolidBrush(rgb(0x1C, 0x1C, 0x22));
    FillRect(mem, &rect, bg);
    let _ = DeleteObject(HGDIOBJ(bg.0));

    STATE.with(|s| {
        let guard = s.borrow();
        let Some(state) = guard.as_ref() else { return };
        let Some(view) = state.view.as_ref() else {
            return;
        };
        let sc = state.scale;
        let px = |v: f32| (v * sc) as i32;

        // Status dot.
        let (text, (r, g, b)) = label(view);
        let dot = CreateSolidBrush(rgb(r, g, b));
        let old_brush = SelectObject(mem, HGDIOBJ(dot.0));
        let old_pen = SelectObject(mem, GetStockObject(NULL_PEN));
        let cy = h / 2;
        let _ = RoundRect(
            mem,
            px(16.0),
            cy - px(5.0),
            px(27.0),
            cy + px(6.0),
            px(11.0),
            px(11.0),
        );

        // Level bars while recording, a pulsing bar otherwise.
        let bar_brush = CreateSolidBrush(rgb(0xE5, 0xE7, 0xEB));
        SelectObject(mem, HGDIOBJ(bar_brush.0));
        let bars_right = w - px(16.0);
        let bar_w = px(4.0).max(2);
        let gap = px(3.0).max(1);
        let max_h = (h as f32 * 0.55) as i32;
        for (i, level) in state.history.iter().enumerate() {
            let x = bars_right - (BARS - i) as i32 * (bar_w + gap);
            let bh = ((level * max_h as f32) as i32).max(px(3.0));
            let _ = RoundRect(
                mem,
                x,
                cy - bh / 2,
                x + bar_w,
                cy + bh / 2 + 1,
                bar_w,
                bar_w,
            );
        }
        SelectObject(mem, old_brush);
        SelectObject(mem, old_pen);
        let _ = DeleteObject(HGDIOBJ(dot.0));
        let _ = DeleteObject(HGDIOBJ(bar_brush.0));

        // Label.
        let font = CreateFontW(
            -px(14.0),
            0,
            0,
            0,
            FW_SEMIBOLD.0 as i32,
            0,
            0,
            0,
            DEFAULT_CHARSET,
            OUT_DEFAULT_PRECIS,
            CLIP_DEFAULT_PRECIS,
            CLEARTYPE_QUALITY,
            0,
            w!("Segoe UI"),
        );
        let old_font = SelectObject(mem, HGDIOBJ(font.0));
        SetBkMode(mem, TRANSPARENT);
        SetTextColor(mem, rgb(0xF3, 0xF4, 0xF6));
        let mut text_rect = RECT {
            left: px(36.0),
            top: 0,
            right: bars_right - BARS as i32 * (bar_w + gap) - px(8.0),
            bottom: h,
        };
        let mut wide: Vec<u16> = text.encode_utf16().collect();
        DrawTextW(
            mem,
            &mut wide,
            &mut text_rect,
            DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS,
        );
        SelectObject(mem, old_font);
        let _ = DeleteObject(HGDIOBJ(font.0));
    });

    let _ = BitBlt(hdc, 0, 0, w, h, Some(mem), 0, 0, SRCCOPY);
    SelectObject(mem, old_bmp);
    let _ = DeleteObject(HGDIOBJ(bmp.0));
    let _ = DeleteDC(mem);
    let _ = EndPaint(hwnd, &ps);
}

/// Advances the bar animation; returns false when a message has expired.
fn tick() -> bool {
    STATE.with(|s| {
        let mut guard = s.borrow_mut();
        let Some(state) = guard.as_mut() else {
            return true;
        };
        let next = match &state.view {
            Some(View::Recording { level, .. }) => f32::from_bits(level.load(Ordering::Relaxed)),
            Some(View::Transcribing) | Some(View::Enhancing) => {
                // Travelling wave while waiting for the provider.
                let t = std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map(|d| d.as_millis() as f32 / 1000.0)
                    .unwrap_or(0.0);
                let phase = state.history.len() as f32;
                0.25 + 0.2 * ((t * 6.0 + phase).sin() + 1.0) / 2.0
            }
            Some(View::Message { until, .. }) => {
                if Instant::now() > *until {
                    return false;
                }
                0.0
            }
            None => 0.0,
        };
        state.history.pop_front();
        state.history.push_back(next);
        true
    })
}

unsafe extern "system" fn wnd_proc(
    hwnd: HWND,
    msg: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    match msg {
        WM_PAINT => {
            paint(hwnd);
            LRESULT(0)
        }
        WM_TIMER => {
            if tick() {
                let _ = InvalidateRect(Some(hwnd), None, false);
            } else {
                let _ = KillTimer(Some(hwnd), TIMER_ID);
                let _ = ShowWindow(hwnd, SW_HIDE);
            }
            LRESULT(0)
        }
        WM_MOUSEACTIVATE => LRESULT(MA_NOACTIVATE as isize),
        WM_LBUTTONUP => {
            STATE.with(|s| {
                if let Some(state) = s.borrow().as_ref() {
                    let _ =
                        PostMessageW(Some(state.owner), WM_OVERLAY_CLICKED, WPARAM(0), LPARAM(0));
                }
            });
            LRESULT(0)
        }
        _ => DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}
