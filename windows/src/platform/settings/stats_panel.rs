//! The dashboard's statistics panel: four tiles, a words-per-day chart and
//! the most used apps, painted with GDI.

use super::super::gdi::{self, BufferedPaint, rgb};
use crate::stats::{self, Stats};
use std::cell::RefCell;
use windows::Win32::Foundation::{COLORREF, HWND, LPARAM, LRESULT, RECT, WPARAM};
use windows::Win32::Graphics::Gdi::{
    COLOR_WINDOW, DRAW_TEXT_FORMAT, DT_CENTER, DT_END_ELLIPSIS, DT_LEFT, DT_SINGLELINE, DT_VCENTER, FW_BOLD, FW_NORMAL,
    FW_SEMIBOLD, GetSysColorBrush, InvalidateRect,
};
use windows::Win32::UI::HiDpi::GetDpiForWindow;
use windows::Win32::UI::WindowsAndMessaging::{
    DefWindowProcW, IDC_ARROW, LoadCursorW, RegisterClassW, WM_PAINT, WNDCLASSW,
};
use windows::core::{PCWSTR, w};

pub const CLASS: PCWSTR = w!("VoiceInkStatsPanel");

const MUTED: COLORREF = rgb(0x6B, 0x72, 0x80);
const INK: COLORREF = rgb(0x11, 0x18, 0x27);
const ACCENT: COLORREF = rgb(0x25, 0x63, 0xEB);
const TILE: COLORREF = rgb(0xF3, 0xF4, 0xF6);
const EMPTY_BAR: COLORREF = rgb(0xD1, 0xD5, 0xDB);
const BASE_DPI: f32 = 96.0;

const TILE_HEIGHT: f32 = 92.0;
const GAP: f32 = 12.0;
const RADIUS: f32 = 12.0;
const PADDING: f32 = 14.0;
/// Share of the width used by the chart; the app list takes the rest.
const CHART_SHARE: f32 = 0.64;
const APP_ROW: f32 = 26.0;

thread_local! {
    static STATS: RefCell<Stats> = RefCell::new(Stats::default());
}

pub fn register(instance: windows::Win32::Foundation::HINSTANCE) {
    // SAFETY: a static class name and a valid window procedure.
    unsafe {
        RegisterClassW(&WNDCLASSW {
            lpfnWndProc: Some(wnd_proc),
            hInstance: instance,
            lpszClassName: CLASS,
            hCursor: LoadCursorW(None, IDC_ARROW).unwrap_or_default(),
            ..Default::default()
        });
    }
}

/// Shows new numbers.
pub fn update(panel: HWND, stats: Stats) {
    STATS.with(|s| *s.borrow_mut() = stats);
    // SAFETY: repaints our own window.
    let _ = unsafe { InvalidateRect(Some(panel), None, false) };
}

unsafe extern "system" fn wnd_proc(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    if msg == WM_PAINT {
        STATS.with(|s| paint(hwnd, &s.borrow()));
        return LRESULT(0);
    }
    // SAFETY: default handling for everything else.
    unsafe { DefWindowProcW(hwnd, msg, wparam, lparam) }
}

/// Fonts and scale for one paint pass.
struct Painter {
    canvas: BufferedPaint,
    scale: f32,
    font: gdi::Owned,
    heading: gdi::Owned,
    big: gdi::Owned,
}

impl Painter {
    fn px(&self, value: f32) -> i32 {
        (value * self.scale).round() as i32
    }

    fn text(&self, text: &str, rect: RECT, font: &gdi::Owned, color: COLORREF, align: DRAW_TEXT_FORMAT) {
        self.canvas.text(text, rect, font, color, align | DT_SINGLELINE | DT_VCENTER);
    }
}

fn paint(hwnd: HWND, stats: &Stats) {
    // SAFETY: no preconditions.
    let scale = unsafe { GetDpiForWindow(hwnd) } as f32 / BASE_DPI;
    let points = |pt: f32| (pt * BASE_DPI * scale / 72.0).round() as i32;
    let p = Painter {
        canvas: BufferedPaint::begin(hwnd),
        scale,
        font: gdi::font(points(9.0), FW_NORMAL),
        heading: gdi::font(points(10.5), FW_SEMIBOLD),
        big: gdi::font(points(18.0), FW_BOLD),
    };
    // SAFETY: system brushes need no cleanup.
    p.canvas.fill(&p.canvas.rect, unsafe { GetSysColorBrush(COLOR_WINDOW) });
    paint_tiles(&p, stats);
    let top = p.px(TILE_HEIGHT + 16.0);
    let chart_right = (p.canvas.rect.right as f32 * CHART_SHARE) as i32;
    paint_chart(&p, stats, top, chart_right);
    paint_top_apps(&p, stats, top, chart_right + p.px(GAP));
}

fn paint_tiles(p: &Painter, s: &Stats) {
    let plural = if s.streak_days == 1 { "" } else { "s" };
    let tiles = [
        ("Words dictated", stats::format_count(s.words), format!("{} sessions", stats::format_count(s.sessions))),
        ("Time saved", stats::format_duration(s.time_saved_secs), format!("vs typing at {} WPM", stats::TYPING_WPM)),
        (
            "Speaking speed",
            format!("{:.0} WPM", s.wpm),
            format!("{} recorded", stats::format_duration(s.duration_secs)),
        ),
        (
            "Streak",
            format!("{} day{plural}", s.streak_days),
            format!("{} AI-enhanced", stats::format_count(s.enhanced_sessions)),
        ),
    ];
    let gap = p.px(GAP);
    let width = (p.canvas.rect.right - gap * 3) / 4;
    let left_aligned = DT_LEFT | DT_END_ELLIPSIS;
    for (i, (label, value, detail)) in tiles.iter().enumerate() {
        let x = i as i32 * (width + gap);
        p.canvas.round_rect(RECT { left: x, top: 0, right: x + width, bottom: p.px(TILE_HEIGHT) }, p.px(RADIUS), TILE);
        let line = |top: f32, height: f32| RECT {
            left: x + p.px(PADDING),
            top: p.px(top),
            right: x + width - p.px(10.0),
            bottom: p.px(top + height),
        };
        let value_color = if i == 1 { ACCENT } else { INK };
        p.text(label, line(8.0, 22.0), &p.font, MUTED, left_aligned);
        p.text(value, line(30.0, 34.0), &p.big, value_color, left_aligned);
        p.text(detail, line(64.0, 20.0), &p.font, MUTED, left_aligned);
    }
}

fn paint_chart(p: &Painter, s: &Stats, top: i32, right: i32) {
    let bottom = p.canvas.rect.bottom;
    p.canvas.round_rect(RECT { left: 0, top, right, bottom }, p.px(RADIUS), TILE);
    let heading = RECT { left: p.px(PADDING), top: top + p.px(6.0), right, bottom: top + p.px(30.0) };
    p.text("Words per day — last 14 days", heading, &p.heading, INK, DT_LEFT);

    let max = s.daily_words.iter().map(|d| d.1).max().unwrap_or(0).max(1);
    let days = s.daily_words.len().max(1) as i32;
    let (plot_left, plot_right) = (p.px(PADDING), right - p.px(PADDING));
    let (plot_top, plot_bottom) = (top + p.px(40.0), bottom - p.px(26.0));
    let slot = (plot_right - plot_left) / days;
    let bar_width = (slot as f32 * 0.6) as i32;
    for (i, (date, words)) in s.daily_words.iter().enumerate() {
        let x = plot_left + i as i32 * slot + (slot - bar_width) / 2;
        let height = ((*words as f32 / max as f32) * (plot_bottom - plot_top) as f32) as i32;
        let bar = RECT { left: x, top: plot_bottom - height.max(p.px(2.0)), right: x + bar_width, bottom: plot_bottom };
        p.canvas.round_rect(bar, p.px(4.0), if *words > 0 { ACCENT } else { EMPTY_BAR });
        // Label every other day, always including today.
        let labeled = i % 2 == (s.daily_words.len() + 1) % 2 || i + 1 == s.daily_words.len();
        if labeled {
            let rect = RECT {
                left: x - p.px(8.0),
                top: plot_bottom + p.px(4.0),
                right: x + bar_width + p.px(8.0),
                bottom: bottom - p.px(4.0),
            };
            p.text(&date.format("%d").to_string(), rect, &p.font, MUTED, DT_CENTER);
        }
    }
}

fn paint_top_apps(p: &Painter, s: &Stats, top: i32, left: i32) {
    let (right, bottom) = (p.canvas.rect.right, p.canvas.rect.bottom);
    p.canvas.round_rect(RECT { left, top, right, bottom }, p.px(RADIUS), TILE);
    let inset = left + p.px(PADDING);
    p.text(
        "Top apps",
        RECT { left: inset, top: top + p.px(6.0), right, bottom: top + p.px(30.0) },
        &p.heading,
        INK,
        DT_LEFT,
    );
    if s.top_apps.is_empty() {
        let rect = RECT { left: inset, top: top + p.px(40.0), right: right - p.px(10.0), bottom: top + p.px(64.0) };
        p.text("Dictate something to see stats", rect, &p.font, MUTED, DT_LEFT | DT_END_ELLIPSIS);
    }
    for (i, (app, count)) in s.top_apps.iter().enumerate() {
        let y = top + p.px(40.0 + i as f32 * APP_ROW);
        let row = |l: i32, r: i32| RECT { left: l, top: y, right: r, bottom: y + p.px(24.0) };
        p.text(app.trim_end_matches(".exe"), row(inset, right - p.px(60.0)), &p.font, INK, DT_LEFT | DT_END_ELLIPSIS);
        p.text(&count.to_string(), row(right - p.px(56.0), right - p.px(PADDING)), &p.font, MUTED, DT_CENTER);
    }
}
