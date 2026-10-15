//! The floating recorder pill (macOS mini/notch recorder).
//!
//! A topmost, non-activating layered window so the focused app keeps keyboard
//! focus — essential for pasting into it afterwards. Clicking it stops the
//! recording. The animation model ([`Animation`]) is separate from painting.

use super::error::{Context, Result};
use super::gdi::{BufferedPaint, font, rgb, solid_brush};
use crate::config::OverlayPosition;
use std::cell::RefCell;
use std::collections::VecDeque;
use std::sync::Arc;
use std::sync::atomic::{AtomicU32, Ordering};
use std::time::Instant;
use windows::Win32::Foundation::{COLORREF, HWND, LPARAM, LRESULT, RECT, WPARAM};
use windows::Win32::Graphics::Gdi::{
    CreateRoundRectRgn, DT_END_ELLIPSIS, DT_LEFT, DT_SINGLELINE, DT_VCENTER, FW_SEMIBOLD, GetMonitorInfoW, HBRUSH,
    InvalidateRect, MONITOR_DEFAULTTOPRIMARY, MONITORINFO, MonitorFromWindow, SetWindowRgn,
};
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::UI::HiDpi::{GetDpiForMonitor, MDT_EFFECTIVE_DPI};
use windows::Win32::UI::WindowsAndMessaging::{
    CS_HREDRAW, CS_VREDRAW, CreateWindowExW, DefWindowProcW, GetForegroundWindow, HWND_TOPMOST, IDC_HAND, KillTimer,
    LWA_ALPHA, LoadCursorW, MA_NOACTIVATE, PostMessageW, RegisterClassW, SW_HIDE, SW_SHOWNOACTIVATE, SWP_NOACTIVATE,
    SetLayeredWindowAttributes, SetTimer, SetWindowPos, ShowWindow, WM_APP, WM_LBUTTONUP, WM_MOUSEACTIVATE, WM_PAINT,
    WM_TIMER, WNDCLASSW, WS_EX_LAYERED, WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW, WS_EX_TOPMOST, WS_POPUP,
};
use windows::core::w;

/// Posted to the owner when the user clicks the overlay.
pub const WM_OVERLAY_CLICKED: u32 = WM_APP + 6;

const TIMER_ID: usize = 1;
/// ~30 fps animation.
const FRAME_MS: u32 = 33;
const BASE_WIDTH: i32 = 236;
const BASE_HEIGHT: i32 = 44;
const SCREEN_MARGIN: f32 = 24.0;
const BARS: usize = 14;
const OPACITY: u8 = 240;
const BASE_DPI: f32 = 96.0;

const BACKGROUND: COLORREF = rgb(0x1C, 0x1C, 0x22);
const BAR_COLOR: COLORREF = rgb(0xE5, 0xE7, 0xEB);
const TEXT_COLOR: COLORREF = rgb(0xF3, 0xF4, 0xF6);
const RECORDING_COLOR: COLORREF = rgb(0xEF, 0x44, 0x44);
const TRANSCRIBING_COLOR: COLORREF = rgb(0x3B, 0x82, 0xF6);
const ENHANCING_COLOR: COLORREF = rgb(0xA8, 0x55, 0xF7);
const MESSAGE_COLOR: COLORREF = rgb(0xF5, 0x9E, 0x0B);

/// What the pill shows.
#[derive(Debug, Clone)]
pub enum View {
    Recording { started: Instant, level: Arc<AtomicU32>, mode: Option<String> },
    Transcribing,
    Enhancing,
    Message { text: String, until: Instant },
}

impl View {
    fn label(&self) -> (String, COLORREF) {
        match self {
            View::Recording { started, mode, .. } => {
                let secs = started.elapsed().as_secs();
                let clock = format!("{}:{:02}", secs / 60, secs % 60);
                let text = mode.as_ref().map_or_else(|| clock.clone(), |m| format!("{clock}  ·  {m}"));
                (text, RECORDING_COLOR)
            }
            View::Transcribing => ("Transcribing…".into(), TRANSCRIBING_COLOR),
            View::Enhancing => ("Enhancing…".into(), ENHANCING_COLOR),
            View::Message { text, .. } => (text.clone(), MESSAGE_COLOR),
        }
    }
}

/// The current view plus the scrolling level bars.
struct Animation {
    view: Option<View>,
    bars: VecDeque<f32>,
    created: Instant,
}

impl Animation {
    fn new() -> Self {
        Self { view: None, bars: VecDeque::from(vec![0.0; BARS]), created: Instant::now() }
    }

    fn show(&mut self, view: View) {
        self.view = Some(view);
        self.bars.iter_mut().for_each(|v| *v = 0.0);
    }

    /// Advances one frame; returns false when a message has expired.
    fn tick(&mut self) -> bool {
        let next = match &self.view {
            Some(View::Recording { level, .. }) => f32::from_bits(level.load(Ordering::Relaxed)),
            // A travelling wave while waiting for the provider.
            Some(View::Transcribing | View::Enhancing) => {
                let t = self.created.elapsed().as_secs_f32();
                0.25 + 0.1 * ((t * 6.0).sin() + 1.0)
            }
            Some(View::Message { until, .. }) if Instant::now() > *until => return false,
            Some(View::Message { .. }) | None => 0.0,
        };
        self.bars.pop_front();
        self.bars.push_back(next);
        true
    }
}

struct OverlayState {
    owner: HWND,
    animation: Animation,
    scale: f32,
}

thread_local! {
    static STATE: RefCell<Option<OverlayState>> = const { RefCell::new(None) };
}

fn with_state<R>(f: impl FnOnce(&mut OverlayState) -> R) -> Option<R> {
    STATE.with(|s| s.borrow_mut().as_mut().map(f))
}

pub struct Overlay {
    hwnd: HWND,
    position: OverlayPosition,
}

impl Overlay {
    /// # Errors
    /// Fails when the window cannot be created.
    pub fn create(owner: HWND, position: OverlayPosition) -> Result<Overlay> {
        let class = w!("VoiceInkRecorderOverlay");
        // SAFETY: registering a class with a static name and a valid window
        // procedure, then creating a popup of that class.
        let hwnd = unsafe {
            let instance = GetModuleHandleW(None).context("module handle")?;
            RegisterClassW(&WNDCLASSW {
                style: CS_HREDRAW | CS_VREDRAW,
                lpfnWndProc: Some(wnd_proc),
                hInstance: instance.into(),
                lpszClassName: class,
                hCursor: LoadCursorW(None, IDC_HAND).unwrap_or_default(),
                ..Default::default()
            });
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
            .context("create the recorder overlay")?;
            let _ = SetLayeredWindowAttributes(hwnd, COLORREF(0), OPACITY, LWA_ALPHA);
            hwnd
        };
        STATE.with(|s| *s.borrow_mut() = Some(OverlayState { owner, animation: Animation::new(), scale: 1.0 }));
        Ok(Overlay { hwnd, position })
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
        with_state(|s| s.animation.show(view));
        self.place();
        // SAFETY: our own window; the timer is killed in `hide`.
        unsafe {
            let _ = ShowWindow(self.hwnd, SW_SHOWNOACTIVATE);
            SetTimer(Some(self.hwnd), TIMER_ID, FRAME_MS, None);
            let _ = InvalidateRect(Some(self.hwnd), None, false);
        }
    }

    pub fn hide(&self) {
        with_state(|s| s.animation.view = None);
        // SAFETY: our own window and timer.
        unsafe {
            let _ = KillTimer(Some(self.hwnd), TIMER_ID);
            let _ = ShowWindow(self.hwnd, SW_HIDE);
        }
    }

    /// Positions the pill on the monitor of the focused window, DPI-scaled.
    fn place(&self) {
        let mut info = MONITORINFO { cbSize: size_of::<MONITORINFO>() as u32, ..Default::default() };
        let (mut dpi_x, mut dpi_y) = (96u32, 96u32);
        // SAFETY: valid out-parameters; MonitorFromWindow always returns a monitor.
        let monitor = unsafe {
            let monitor = MonitorFromWindow(GetForegroundWindow(), MONITOR_DEFAULTTOPRIMARY);
            if !GetMonitorInfoW(monitor, &raw mut info).as_bool() {
                return;
            }
            let _ = GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, &raw mut dpi_x, &raw mut dpi_y);
            monitor
        };
        let _ = monitor;
        let scale = dpi_x as f32 / BASE_DPI;
        with_state(|s| s.scale = scale);

        let width = (BASE_WIDTH as f32 * scale) as i32;
        let height = (BASE_HEIGHT as f32 * scale) as i32;
        let work = info.rcWork;
        let x = work.left + (work.right - work.left - width) / 2;
        let margin = (SCREEN_MARGIN * scale) as i32;
        let y = match self.position {
            OverlayPosition::TopCenter => work.top + margin,
            _ => work.bottom - height - margin,
        };
        // SAFETY: our own window; the window takes ownership of the region.
        unsafe {
            let _ = SetWindowPos(self.hwnd, Some(HWND_TOPMOST), x, y, width, height, SWP_NOACTIVATE);
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

fn paint(hwnd: HWND) {
    let canvas = BufferedPaint::begin(hwnd);
    let background = solid_brush(BACKGROUND);
    canvas.fill(&canvas.rect, HBRUSH(background.raw().0));

    with_state(|state| {
        let Some(view) = &state.animation.view else { return };
        let px = |v: f32| (v * state.scale) as i32;
        let (w, h) = (canvas.rect.right, canvas.rect.bottom);
        let cy = h / 2;
        let (text, dot_color) = view.label();

        // Status dot.
        canvas.round_rect(
            RECT { left: px(16.0), top: cy - px(5.0), right: px(27.0), bottom: cy + px(6.0) },
            px(11.0),
            dot_color,
        );

        // Level bars.
        let bars_right = w - px(16.0);
        let bar_w = px(4.0).max(2);
        let gap = px(3.0).max(1);
        let max_h = (h as f32 * 0.55) as i32;
        for (i, level) in state.animation.bars.iter().enumerate() {
            let x = bars_right - (BARS - i) as i32 * (bar_w + gap);
            let bar_h = ((level * max_h as f32) as i32).max(px(3.0));
            canvas.round_rect(
                RECT { left: x, top: cy - bar_h / 2, right: x + bar_w, bottom: cy + bar_h / 2 },
                bar_w,
                BAR_COLOR,
            );
        }

        let label_font = font(px(14.0), FW_SEMIBOLD);
        let text_rect =
            RECT { left: px(36.0), top: 0, right: bars_right - BARS as i32 * (bar_w + gap) - px(8.0), bottom: h };
        canvas.text(&text, text_rect, &label_font, TEXT_COLOR, DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
    });
}

unsafe extern "system" fn wnd_proc(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    match msg {
        WM_PAINT => paint(hwnd),
        WM_TIMER => {
            let keep_running = with_state(|s| s.animation.tick()).unwrap_or(true);
            // SAFETY: our own window and timer.
            unsafe {
                if keep_running {
                    let _ = InvalidateRect(Some(hwnd), None, false);
                } else {
                    let _ = KillTimer(Some(hwnd), TIMER_ID);
                    let _ = ShowWindow(hwnd, SW_HIDE);
                }
            }
        }
        WM_MOUSEACTIVATE => return LRESULT(MA_NOACTIVATE as isize),
        WM_LBUTTONUP => {
            if let Some(owner) = with_state(|s| s.owner) {
                // SAFETY: posting to the owning app window.
                let _ = unsafe { PostMessageW(Some(owner), WM_OVERLAY_CLICKED, WPARAM(0), LPARAM(0)) };
            }
        }
        // SAFETY: default processing with the original arguments.
        _ => return unsafe { DefWindowProcW(hwnd, msg, wparam, lparam) },
    }
    LRESULT(0)
}
