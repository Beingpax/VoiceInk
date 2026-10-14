//! Dashboard & Settings window — the Windows counterpart of the macOS
//! dashboard and settings views, built from standard Win32 controls.
//!
//! The window edits a working copy of the configuration loaded from disk;
//! **Save** writes `config.json`, stores typed API keys (DPAPI) and posts
//! [`WM_SETTINGS_SAVED`] to the app so it reloads hotkeys and options.

use super::icon::{create_icon, IconState};
use super::{autostart, capture, clipboard, wide};
use crate::config::{
    self, parse_hotkey, Config, EnhancementProvider, HotkeyMode, OverlayPosition, PasteMethod,
    SendKey, TranscriptionProvider, LANGUAGES,
};
use crate::credentials;
use crate::history::{self, Entry, Status};
use crate::prompts::CustomPrompt;
use crate::stats::{self, Stats};
use crate::text::parse_replacement_lines as parse_replacements;
use std::cell::RefCell;
use windows::core::{w, PCWSTR};
use windows::Win32::Foundation::{COLORREF, HWND, LPARAM, LRESULT, RECT, WPARAM};
use windows::Win32::Graphics::Gdi::{
    BeginPaint, BitBlt, CreateCompatibleBitmap, CreateCompatibleDC, CreateFontW, CreateSolidBrush,
    DeleteDC, DeleteObject, DrawTextW, EndPaint, FillRect, GetStockObject, GetSysColorBrush,
    InvalidateRect, RoundRect, SelectObject, SetBkMode, SetTextColor, CLEARTYPE_QUALITY,
    CLIP_DEFAULT_PRECIS, COLOR_WINDOW, DEFAULT_CHARSET, DT_CENTER, DT_END_ELLIPSIS, DT_LEFT,
    DT_SINGLELINE, DT_VCENTER, FONT_WEIGHT, FW_BOLD, FW_NORMAL, FW_SEMIBOLD, HBRUSH, HDC, HFONT,
    HGDIOBJ, NULL_PEN, OUT_DEFAULT_PRECIS, PAINTSTRUCT, SRCCOPY, TRANSPARENT,
};
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::UI::HiDpi::GetDpiForWindow;
use windows::Win32::UI::WindowsAndMessaging::{
    AdjustWindowRectEx, CreateWindowExW, DefWindowProcW, DestroyWindow, GetClientRect,
    GetWindowTextLengthW, GetWindowTextW, IsWindow, LoadCursorW, MessageBoxW, PostMessageW,
    RegisterClassW, SendMessageW, SetForegroundWindow, SetWindowPos, SetWindowTextW, ShowWindow,
    CW_USEDEFAULT, HMENU, ICON_BIG, ICON_SMALL, IDC_ARROW, IDYES, MB_ICONERROR, MB_ICONWARNING,
    MB_OK, MB_YESNO, SWP_NOMOVE, SWP_NOZORDER, SW_HIDE, SW_SHOW, SW_SHOWNORMAL, WINDOW_EX_STYLE,
    WINDOW_STYLE, WM_APP, WM_CLOSE, WM_COMMAND, WM_CTLCOLORSTATIC, WM_DESTROY, WM_PAINT,
    WM_SETFONT, WM_SETICON, WNDCLASSW, WS_CAPTION, WS_CHILD, WS_EX_CLIENTEDGE, WS_EX_CONTROLPARENT,
    WS_MINIMIZEBOX, WS_OVERLAPPED, WS_SYSMENU, WS_TABSTOP, WS_VSCROLL,
};

/// Posted to the app window after the settings were written to disk.
pub const WM_SETTINGS_SAVED: u32 = WM_APP + 8;

// Win32 control styles and messages (values from WinUser.h / CommCtrl.h).
const BS_DEFPUSHBUTTON: u32 = 0x1;
const BS_AUTOCHECKBOX: u32 = 0x3;
const BM_GETCHECK: u32 = 0xF0;
const BM_SETCHECK: u32 = 0xF1;
const CBS_DROPDOWN: u32 = 0x2;
const CBS_DROPDOWNLIST: u32 = 0x3;
const CB_ADDSTRING: u32 = 0x143;
const CB_GETCURSEL: u32 = 0x147;
const CB_RESETCONTENT: u32 = 0x14B;
const CB_SETCURSEL: u32 = 0x14E;
const CB_SETMINVISIBLE: u32 = 0x1701;
const CBN_SELCHANGE: u32 = 1;
const LBS_NOTIFY: u32 = 0x1;
const LBS_NOINTEGRALHEIGHT: u32 = 0x100;
const LB_ADDSTRING: u32 = 0x180;
const LB_RESETCONTENT: u32 = 0x184;
const LB_SETCURSEL: u32 = 0x186;
const LB_GETCURSEL: u32 = 0x188;
const LB_SETITEMHEIGHT: u32 = 0x1A0;
const LBN_SELCHANGE: u32 = 1;
const LBN_DBLCLK: u32 = 2;
const ES_MULTILINE: u32 = 0x4;
const ES_PASSWORD: u32 = 0x20;
const ES_AUTOVSCROLL: u32 = 0x40;
const ES_AUTOHSCROLL: u32 = 0x80;
const ES_WANTRETURN: u32 = 0x1000;
const ES_NUMBER: u32 = 0x2000;
const EM_SETCUEBANNER: u32 = 0x1501;

// Layout (device-independent pixels).
const CLIENT_W: i32 = 880;
const CLIENT_H: i32 = 620;
const NAV_W: i32 = 180;
const LEFT: i32 = 212;
const CONTENT_W: i32 = CLIENT_W - LEFT - 24;
const LABEL_W: i32 = 190;
const FIELD_X: i32 = LEFT + LABEL_W;
const FIELD_W: i32 = CONTENT_W - LABEL_W;
const ROW: i32 = 34;

const PAGES: &[&str] = &[
    "Dashboard",
    "General",
    "Transcription",
    "AI Enhancement",
    "Prompts",
    "Dictionary",
    "Snippets",
    "Command Mode",
    "Output",
    "History",
];

// Control ids that trigger actions.
const ID_NAV: usize = 1000;
const ID_SAVE: usize = 1001;
const ID_CLOSE: usize = 1002;
const ID_T_PROVIDER: usize = 1010;
const ID_T_REMOVE_KEY: usize = 1011;
const ID_E_PROVIDER: usize = 1020;
const ID_E_REMOVE_KEY: usize = 1021;
const ID_P_SELECT: usize = 1030;
const ID_P_NEW: usize = 1031;
const ID_P_DELETE: usize = 1032;
const ID_RECENT: usize = 1040;
const ID_EXPORT: usize = 1041;
const ID_CLEAR_HISTORY: usize = 1042;
const ID_OPEN_FOLDER: usize = 1043;
const ID_EDIT_MODES: usize = 1044;
const ID_REFRESH: usize = 1045;
const ID_C_PROVIDER: usize = 1050;

const HOTKEY_MODES: [(HotkeyMode, &str); 3] = [
    (HotkeyMode::Hybrid, "Tap to toggle, hold to talk"),
    (HotkeyMode::Toggle, "Toggle (press to start / stop)"),
    (HotkeyMode::PushToTalk, "Push to talk (hold)"),
];
const OVERLAY_POSITIONS: [(OverlayPosition, &str); 3] = [
    (OverlayPosition::BottomCenter, "Bottom center"),
    (OverlayPosition::TopCenter, "Top center"),
    (OverlayPosition::Hidden, "Hidden"),
];
const PASTE_METHODS: [(PasteMethod, &str); 3] = [
    (PasteMethod::CtrlV, "Clipboard + Ctrl+V (recommended)"),
    (
        PasteMethod::ShiftInsert,
        "Clipboard + Shift+Insert (terminals)",
    ),
    (PasteMethod::Type, "Simulated typing (no clipboard)"),
];
const SEND_KEYS: [(SendKey, &str); 4] = [
    (SendKey::None, "Nothing"),
    (SendKey::Enter, "Enter"),
    (SendKey::ShiftEnter, "Shift+Enter"),
    (SendKey::CtrlEnter, "Ctrl+Enter"),
];

#[derive(Default)]
struct Controls {
    status: HWND,
    stats_panel: HWND,
    recent: HWND,
    // General
    hk_record: HWND,
    hk_mode: HWND,
    hk_threshold: HWND,
    hk_cancel: HWND,
    hk_paste_last: HWND,
    microphone: HWND,
    overlay: HWND,
    sounds: HWND,
    mute: HWND,
    autostart: HWND,
    modes_label: HWND,
    // Transcription
    t_provider: HWND,
    t_model: HWND,
    t_language: HWND,
    t_endpoint: HWND,
    t_key: HWND,
    t_key_status: HWND,
    t_filter: HWND,
    t_formatting: HWND,
    t_fillers: HWND,
    // Enhancement
    e_enabled: HWND,
    e_provider: HWND,
    e_model: HWND,
    e_prompt: HWND,
    e_key: HWND,
    e_key_status: HWND,
    e_endpoint_label: HWND,
    e_endpoint: HWND,
    e_clipboard: HWND,
    e_selection: HWND,
    e_window: HWND,
    e_skip_short: HWND,
    e_short_words: HWND,
    e_timeout: HWND,
    // Prompts
    p_select: HWND,
    p_title: HWND,
    p_system: HWND,
    p_text: HWND,
    // Dictionary
    vocabulary: HWND,
    replacements: HWND,
    // Snippets
    snippets: HWND,
    // Command Mode
    c_enabled: HWND,
    c_hotkey: HWND,
    c_provider: HWND,
    c_model: HWND,
    // Output
    o_method: HWND,
    o_restore: HWND,
    o_restore_delay: HWND,
    o_send_key: HWND,
    o_space: HWND,
    // History
    h_enabled: HWND,
    h_audio: HWND,
    h_max: HWND,
}

struct Ui {
    hwnd: HWND,
    owner: HWND,
    scale: f32,
    font: HFONT,
    title_font: HFONT,
    nav: HWND,
    pages: Vec<Vec<HWND>>,
    page: usize,
    config: Config,
    c: Controls,
    /// Index in `config.prompts` shown in the prompt editor.
    prompt_index: usize,
    devices: Vec<String>,
    recent: Vec<Entry>,
}

thread_local! {
    static UI: RefCell<Option<Ui>> = const { RefCell::new(None) };
    static STATS: RefCell<Stats> = RefCell::new(Stats::default());
    static FONTS: RefCell<(HFONT, HFONT, HFONT)> = RefCell::new(Default::default());
}

// ---------------------------------------------------------------------------
// Small control helpers
// ---------------------------------------------------------------------------

fn get_text(h: HWND) -> String {
    unsafe {
        let len = GetWindowTextLengthW(h);
        let mut buf = vec![0u16; len.max(0) as usize + 1];
        let n = GetWindowTextW(h, &mut buf);
        String::from_utf16_lossy(&buf[..n.max(0) as usize])
    }
}

fn set_text(h: HWND, text: &str) {
    // Edit controls want CRLF line breaks.
    let text = text.replace("\r\n", "\n").replace('\n', "\r\n");
    let w = wide(&text);
    unsafe {
        let _ = SetWindowTextW(h, PCWSTR(w.as_ptr()));
    }
}

fn send(h: HWND, msg: u32, wparam: usize, lparam: isize) -> isize {
    unsafe { SendMessageW(h, msg, Some(WPARAM(wparam)), Some(LPARAM(lparam))).0 }
}

fn is_checked(h: HWND) -> bool {
    send(h, BM_GETCHECK, 0, 0) == 1
}

fn set_checked(h: HWND, on: bool) {
    send(h, BM_SETCHECK, on as usize, 0);
}

fn combo_fill(h: HWND, items: &[String]) {
    send(h, CB_RESETCONTENT, 0, 0);
    for item in items {
        let w = wide(item);
        send(h, CB_ADDSTRING, 0, w.as_ptr() as isize);
    }
}

fn combo_sel(h: HWND) -> Option<usize> {
    let i = send(h, CB_GETCURSEL, 0, 0);
    (i >= 0).then_some(i as usize)
}

fn combo_set(h: HWND, index: usize) {
    send(h, CB_SETCURSEL, index, 0);
}

fn cue(h: HWND, text: &str) {
    let w = wide(text);
    send(h, EM_SETCUEBANNER, 1, w.as_ptr() as isize);
}

fn message(owner: HWND, text: &str, error: bool) {
    let t = wide(text);
    unsafe {
        MessageBoxW(
            Some(owner),
            PCWSTR(t.as_ptr()),
            w!("VoiceInk"),
            MB_OK | if error { MB_ICONERROR } else { MB_ICONWARNING },
        );
    }
}

fn make_font(scale: f32, points: f32, weight: FONT_WEIGHT) -> HFONT {
    unsafe {
        CreateFontW(
            -((points * 96.0 * scale / 72.0).round() as i32),
            0,
            0,
            0,
            weight.0 as i32,
            0,
            0,
            0,
            DEFAULT_CHARSET,
            OUT_DEFAULT_PRECIS,
            CLIP_DEFAULT_PRECIS,
            CLEARTYPE_QUALITY,
            0,
            w!("Segoe UI"),
        )
    }
}

fn key_status(name: &str) -> &'static str {
    if name.is_empty() {
        "Not needed"
    } else if credentials::has(name) {
        "Stored"
    } else {
        "Not set"
    }
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

struct Builder {
    parent: HWND,
    scale: f32,
    font: HFONT,
    page: Vec<HWND>,
}

impl Builder {
    fn px(&self, v: i32) -> i32 {
        (v as f32 * self.scale).round() as i32
    }

    #[allow(clippy::too_many_arguments)]
    fn make(
        &mut self,
        class: PCWSTR,
        text: &str,
        style: u32,
        ex: u32,
        x: i32,
        y: i32,
        w: i32,
        h: i32,
        id: usize,
    ) -> HWND {
        let t = wide(text);
        unsafe {
            let hwnd = CreateWindowExW(
                WINDOW_EX_STYLE(ex),
                class,
                PCWSTR(t.as_ptr()),
                WS_CHILD | WINDOW_STYLE(style),
                self.px(x),
                self.px(y),
                self.px(w),
                self.px(h),
                Some(self.parent),
                Some(HMENU(id as *mut _)),
                GetModuleHandleW(None).ok().map(|m| m.into()),
                None,
            )
            .unwrap_or_default();
            send(hwnd, WM_SETFONT, self.font.0 as usize, 1);
            self.page.push(hwnd);
            hwnd
        }
    }

    fn label(&mut self, text: &str, x: i32, y: i32, w: i32) -> HWND {
        self.make(w!("STATIC"), text, 0, 0, x, y + 4, w, 20, 0)
    }

    fn hint(&mut self, text: &str, y: i32) -> HWND {
        self.make(w!("STATIC"), text, 0, 0, FIELD_X, y, FIELD_W, 20, 0)
    }

    fn row_label(&mut self, text: &str, y: i32) {
        self.label(text, LEFT, y, LABEL_W - 12);
    }

    fn edit(&mut self, y: i32, w: i32, extra: u32) -> HWND {
        self.make(
            w!("EDIT"),
            "",
            WS_TABSTOP.0 | ES_AUTOHSCROLL | extra,
            WS_EX_CLIENTEDGE.0,
            FIELD_X,
            y,
            w,
            24,
            0,
        )
    }

    fn multiline(&mut self, x: i32, y: i32, w: i32, h: i32) -> HWND {
        self.make(
            w!("EDIT"),
            "",
            WS_TABSTOP.0 | WS_VSCROLL.0 | ES_MULTILINE | ES_AUTOVSCROLL | ES_WANTRETURN,
            WS_EX_CLIENTEDGE.0,
            x,
            y,
            w,
            h,
            0,
        )
    }

    fn combo(&mut self, y: i32, w: i32, editable: bool, id: usize) -> HWND {
        let kind = if editable {
            CBS_DROPDOWN
        } else {
            CBS_DROPDOWNLIST
        };
        let h = self.make(
            w!("COMBOBOX"),
            "",
            WS_TABSTOP.0 | WS_VSCROLL.0 | kind,
            0,
            FIELD_X,
            y,
            w,
            300,
            id,
        );
        send(h, CB_SETMINVISIBLE, 14, 0);
        h
    }

    fn check(&mut self, text: &str, x: i32, y: i32, w: i32) -> HWND {
        self.make(
            w!("BUTTON"),
            text,
            WS_TABSTOP.0 | BS_AUTOCHECKBOX,
            0,
            x,
            y,
            w,
            24,
            0,
        )
    }

    fn button(&mut self, text: &str, x: i32, y: i32, w: i32, id: usize) -> HWND {
        self.make(w!("BUTTON"), text, WS_TABSTOP.0, 0, x, y, w, 28, id)
    }

    fn title(&mut self, text: &str, font: HFONT) {
        let h = self.make(w!("STATIC"), text, 0, 0, LEFT, 14, CONTENT_W, 32, 0);
        send(h, WM_SETFONT, font.0 as usize, 1);
    }

    fn finish(&mut self) -> Vec<HWND> {
        std::mem::take(&mut self.page)
    }
}

fn build(ui: &mut Ui) {
    let mut b = Builder {
        parent: ui.hwnd,
        scale: ui.scale,
        font: ui.font,
        page: Vec::new(),
    };
    let c = &mut ui.c;
    let tf = ui.title_font;

    // Always-visible chrome: navigation, status line, Save / Close.
    ui.nav = b.make(
        w!("LISTBOX"),
        "",
        WS_TABSTOP.0 | LBS_NOTIFY | LBS_NOINTEGRALHEIGHT,
        0,
        0,
        0,
        NAV_W,
        CLIENT_H,
        ID_NAV,
    );
    send(ui.nav, LB_SETITEMHEIGHT, 0, b.px(36) as isize);
    for p in PAGES {
        let w = wide(&format!("   {p}"));
        send(ui.nav, LB_ADDSTRING, 0, w.as_ptr() as isize);
    }
    c.status = b.make(w!("STATIC"), "", 0, 0, LEFT, CLIENT_H - 40, 380, 20, 0);
    b.make(
        w!("BUTTON"),
        "Save",
        WS_TABSTOP.0 | BS_DEFPUSHBUTTON,
        0,
        CLIENT_W - 224,
        CLIENT_H - 46,
        96,
        30,
        ID_SAVE,
    );
    b.make(
        w!("BUTTON"),
        "Close",
        WS_TABSTOP.0,
        0,
        CLIENT_W - 120,
        CLIENT_H - 46,
        96,
        30,
        ID_CLOSE,
    );
    for h in b.finish() {
        unsafe {
            let _ = ShowWindow(h, SW_SHOW);
        }
    }

    // 0 Dashboard
    b.title("Dashboard", tf);
    c.stats_panel = b.make(
        w!("VoiceInkStatsPanel"),
        "",
        0,
        0,
        LEFT,
        56,
        CONTENT_W,
        300,
        0,
    );
    b.label(
        "Recent transcriptions — double-click to copy",
        LEFT,
        364,
        420,
    );
    b.button("Refresh", LEFT + CONTENT_W - 220, 362, 100, ID_REFRESH);
    b.button("Export CSV", LEFT + CONTENT_W - 112, 362, 112, ID_EXPORT);
    c.recent = b.make(
        w!("LISTBOX"),
        "",
        WS_TABSTOP.0 | WS_VSCROLL.0 | LBS_NOTIFY | LBS_NOINTEGRALHEIGHT,
        WS_EX_CLIENTEDGE.0,
        LEFT,
        396,
        CONTENT_W,
        CLIENT_H - 396 - 60,
        ID_RECENT,
    );
    ui.pages.push(b.finish());

    // 1 General
    b.title("General", tf);
    let mut y = 64;
    b.row_label("Record shortcut", y);
    c.hk_record = b.edit(y, 200, 0);
    y += 26;
    b.hint(
        "Examples: RightCtrl, F9, Ctrl+Shift+Space, Alt+Q, Mouse4",
        y,
    );
    y += ROW;
    b.row_label("Shortcut behaviour", y);
    c.hk_mode = b.combo(y, 300, false, 0);
    y += ROW;
    b.row_label("Hold threshold (ms)", y);
    c.hk_threshold = b.edit(y, 100, ES_NUMBER);
    y += ROW;
    b.row_label("Cancel shortcut", y);
    c.hk_cancel = b.edit(y, 200, 0);
    y += ROW;
    b.row_label("Paste last transcription", y);
    c.hk_paste_last = b.edit(y, 200, 0);
    y += ROW + 8;
    b.row_label("Microphone", y);
    c.microphone = b.combo(y, FIELD_W, false, 0);
    y += ROW;
    b.row_label("Recorder overlay", y);
    c.overlay = b.combo(y, 200, false, 0);
    y += ROW + 4;
    c.sounds = b.check("Play start / stop sounds", FIELD_X, y, FIELD_W);
    y += 28;
    c.mute = b.check("Mute system audio while recording", FIELD_X, y, FIELD_W);
    y += 28;
    c.autostart = b.check("Start VoiceInk with Windows", FIELD_X, y, FIELD_W);
    y += ROW + 8;
    b.row_label("Modes", y);
    c.modes_label = b.label("", FIELD_X, y, FIELD_W - 210);
    b.button(
        "Edit modes in config.json",
        FIELD_X + FIELD_W - 200,
        y,
        200,
        ID_EDIT_MODES,
    );
    ui.pages.push(b.finish());

    // 2 Transcription
    b.title("Transcription", tf);
    let mut y = 64;
    b.row_label("Provider", y);
    c.t_provider = b.combo(y, 280, false, ID_T_PROVIDER);
    y += ROW;
    b.row_label("Model", y);
    c.t_model = b.combo(y, 280, true, 0);
    y += ROW;
    b.row_label("Language", y);
    c.t_language = b.combo(y, 280, false, 0);
    y += ROW;
    b.row_label("API key", y);
    c.t_key = b.edit(y, 230, ES_PASSWORD);
    b.button("Remove", FIELD_X + 238, y - 2, 80, ID_T_REMOVE_KEY);
    c.t_key_status = b.label("", FIELD_X + 328, y, FIELD_W - 328);
    y += ROW;
    b.row_label("Custom endpoint", y);
    c.t_endpoint = b.edit(y, FIELD_W, 0);
    y += 26;
    b.hint(
        "Used by the Custom provider, e.g. a local whisper.cpp server",
        y,
    );
    y += ROW + 4;
    c.t_filter = b.check(
        "Remove filler words and noise tags like [MUSIC]",
        FIELD_X,
        y,
        FIELD_W,
    );
    y += 28;
    c.t_formatting = b.check(
        "Format long dictations into paragraphs",
        FIELD_X,
        y,
        FIELD_W,
    );
    y += ROW;
    b.row_label("Filler words", y);
    c.t_fillers = b.edit(y, FIELD_W, 0);
    y += 26;
    b.hint("Comma separated", y);
    ui.pages.push(b.finish());

    // 3 AI Enhancement
    b.title("AI Enhancement", tf);
    let mut y = 64;
    c.e_enabled = b.check("Clean up transcripts with AI", FIELD_X, y, FIELD_W);
    y += ROW;
    b.row_label("Provider", y);
    c.e_provider = b.combo(y, 280, false, ID_E_PROVIDER);
    y += ROW;
    b.row_label("Model", y);
    c.e_model = b.combo(y, 280, true, 0);
    y += ROW;
    b.row_label("Prompt", y);
    c.e_prompt = b.combo(y, 280, false, 0);
    y += ROW;
    b.row_label("API key", y);
    c.e_key = b.edit(y, 230, ES_PASSWORD);
    b.button("Remove", FIELD_X + 238, y - 2, 80, ID_E_REMOVE_KEY);
    c.e_key_status = b.label("", FIELD_X + 328, y, FIELD_W - 328);
    y += ROW;
    b.row_label("", y);
    c.e_endpoint_label = b.page.last().copied().unwrap_or_default();
    c.e_endpoint = b.edit(y, FIELD_W, 0);
    y += ROW + 8;
    b.row_label("Context", y);
    c.e_window = b.check("Active window title and app", FIELD_X, y, FIELD_W);
    y += 28;
    c.e_clipboard = b.check("Clipboard text", FIELD_X, y, FIELD_W);
    y += 28;
    c.e_selection = b.check(
        "Selected text (copied when recording starts)",
        FIELD_X,
        y,
        FIELD_W,
    );
    y += ROW + 4;
    c.e_skip_short = b.check("Skip AI for short dictations of at most", FIELD_X, y, 290);
    c.e_short_words = b.make(
        w!("EDIT"),
        "",
        WS_TABSTOP.0 | ES_NUMBER,
        WS_EX_CLIENTEDGE.0,
        FIELD_X + 296,
        y,
        50,
        24,
        0,
    );
    b.label("words", FIELD_X + 352, y, 60);
    y += ROW;
    b.row_label("Timeout (seconds)", y);
    c.e_timeout = b.edit(y, 80, ES_NUMBER);
    ui.pages.push(b.finish());

    // 4 Prompts
    b.title("Prompts", tf);
    let y = 64;
    b.row_label("Prompt", y);
    c.p_select = b.combo(y, 280, false, ID_P_SELECT);
    b.button("New", FIELD_X + 288, y - 2, 76, ID_P_NEW);
    b.button("Delete", FIELD_X + 372, y - 2, 80, ID_P_DELETE);
    b.row_label("Title", y + ROW);
    c.p_title = b.edit(y + ROW, 280, 0);
    c.p_system = b.check(
        "Wrap with VoiceInk's transcription-cleaning rules (recommended)",
        FIELD_X,
        y + 2 * ROW,
        FIELD_W,
    );
    b.label("Instructions", LEFT, y + 3 * ROW, LABEL_W);
    c.p_text = b.multiline(
        LEFT,
        y + 3 * ROW + 26,
        CONTENT_W,
        CLIENT_H - (y + 3 * ROW + 26) - 60,
    );
    ui.pages.push(b.finish());

    // 5 Dictionary
    b.title("Dictionary", tf);
    let half = (CONTENT_W - 16) / 2;
    b.label("Vocabulary — one term per line", LEFT, 60, half);
    b.label(
        "Replacements — one per line: spoken -> written",
        LEFT + half + 16,
        60,
        half,
    );
    c.vocabulary = b.multiline(LEFT, 86, half, CLIENT_H - 86 - 92);
    c.replacements = b.multiline(LEFT + half + 16, 86, half, CLIENT_H - 86 - 92);
    b.make(
        w!("STATIC"),
        "Vocabulary guides spelling of names. Example replacement: voice ink, voice inc -> VoiceInk",
        0,
        0,
        LEFT,
        CLIENT_H - 82,
        CONTENT_W,
        20,
        0,
    );
    ui.pages.push(b.finish());

    // 6 Snippets
    b.title("Snippets", tf);
    b.make(
        w!("STATIC"),
        "Say a trigger phrase and VoiceInk types the saved text. Saying only the trigger inserts the snippet as-is; inside a longer dictation it is expanded after AI clean-up.",
        0,
        0,
        LEFT,
        56,
        CONTENT_W,
        40,
        0,
    );
    b.label(
        "One per line:  trigger => text    (\\n = line break, {date} {time} {datetime})",
        LEFT,
        98,
        CONTENT_W,
    );
    c.snippets = b.multiline(LEFT, 126, CONTENT_W, CLIENT_H - 126 - 92);
    b.make(
        w!("STATIC"),
        "Example:  my calendar link => https://cal.com/yourname",
        0,
        0,
        LEFT,
        CLIENT_H - 82,
        CONTENT_W,
        20,
        0,
    );
    ui.pages.push(b.finish());

    // 7 Command Mode
    b.title("Command Mode", tf);
    b.make(
        w!("STATIC"),
        "Select text in any app, press the Command shortcut and say what to do — \"make this more formal\", \"translate to German\", \"turn this into bullet points\". The result replaces the selection. With nothing selected, the instruction writes new text at the cursor (\"write a polite reply declining the meeting\").",
        0,
        0,
        LEFT,
        56,
        CONTENT_W,
        58,
        0,
    );
    let mut y = 128;
    c.c_enabled = b.check("Enable Command Mode", FIELD_X, y, FIELD_W);
    y += ROW;
    b.row_label("Command shortcut", y);
    c.c_hotkey = b.edit(y, 200, 0);
    y += 26;
    b.hint(
        "Uses the same tap / hold behaviour as the record shortcut",
        y,
    );
    y += ROW;
    b.row_label("AI provider", y);
    c.c_provider = b.combo(y, 280, false, ID_C_PROVIDER);
    y += ROW;
    b.row_label("Model", y);
    c.c_model = b.combo(y, 280, true, 0);
    y += 26;
    b.hint(
        "Leave empty for the provider's default. A capable model works best.",
        y,
    );
    ui.pages.push(b.finish());

    // 8 Output
    b.title("Output", tf);
    let mut y = 64;
    b.row_label("Insert text with", y);
    c.o_method = b.combo(y, 320, false, 0);
    y += ROW + 4;
    c.o_restore = b.check("Restore my clipboard after pasting", FIELD_X, y, FIELD_W);
    y += ROW;
    b.row_label("Restore after (ms)", y);
    c.o_restore_delay = b.edit(y, 100, ES_NUMBER);
    y += ROW;
    b.row_label("Then press", y);
    c.o_send_key = b.combo(y, 200, false, 0);
    y += 26;
    b.hint("\"Finish & Send\": submit chat messages automatically", y);
    y += ROW;
    c.o_space = b.check(
        "Add a trailing space after each dictation",
        FIELD_X,
        y,
        FIELD_W,
    );
    ui.pages.push(b.finish());

    // 7 History
    b.title("History", tf);
    let mut y = 64;
    c.h_enabled = b.check("Keep a history of transcriptions", FIELD_X, y, FIELD_W);
    y += 28;
    c.h_audio = b.check("Also keep the audio recordings", FIELD_X, y, FIELD_W);
    y += ROW;
    b.row_label("Keep at most (entries)", y);
    c.h_max = b.edit(y, 100, ES_NUMBER);
    y += 26;
    b.hint("0 keeps everything", y);
    y += ROW + 8;
    b.button("Export CSV", FIELD_X, y, 130, ID_EXPORT);
    b.button("Open data folder", FIELD_X + 140, y, 150, ID_OPEN_FOLDER);
    b.button(
        "Delete all history",
        FIELD_X + 300,
        y,
        160,
        ID_CLEAR_HISTORY,
    );
    ui.pages.push(b.finish());
}

// ---------------------------------------------------------------------------
// Config <-> controls
// ---------------------------------------------------------------------------

fn transcription_models(p: TranscriptionProvider) -> Vec<String> {
    let mut v: Vec<String> = p.models().iter().map(|s| s.to_string()).collect();
    if v.is_empty() {
        v.push(p.default_model().to_string());
    }
    v
}

fn enhancement_models(p: EnhancementProvider) -> Vec<String> {
    let mut v: Vec<String> = p.models().iter().map(|s| s.to_string()).collect();
    if v.is_empty() && !p.default_model().is_empty() {
        v.push(p.default_model().to_string());
    }
    v
}

impl Ui {
    fn load(&mut self) {
        let cfg = self.config.clone();
        let c = &self.c;

        // General
        set_text(c.hk_record, &cfg.hotkeys.record);
        combo_fill(
            c.hk_mode,
            &HOTKEY_MODES
                .iter()
                .map(|m| m.1.to_string())
                .collect::<Vec<_>>(),
        );
        combo_set(
            c.hk_mode,
            HOTKEY_MODES
                .iter()
                .position(|m| m.0 == cfg.hotkeys.mode)
                .unwrap_or(0),
        );
        set_text(c.hk_threshold, &cfg.hotkeys.hybrid_threshold_ms.to_string());
        set_text(c.hk_cancel, &cfg.hotkeys.cancel);
        set_text(
            c.hk_paste_last,
            cfg.hotkeys.paste_last.as_deref().unwrap_or(""),
        );
        let mut mics = vec!["System default".to_string()];
        mics.extend(self.devices.iter().cloned());
        let configured = cfg
            .audio
            .input_device
            .clone()
            .filter(|d| !d.trim().is_empty());
        if let Some(d) = &configured {
            if !self.devices.iter().any(|x| x == d) {
                mics.push(d.clone());
            }
        }
        combo_fill(c.microphone, &mics);
        combo_set(
            c.microphone,
            configured
                .and_then(|d| mics.iter().position(|m| *m == d))
                .unwrap_or(0),
        );
        combo_fill(
            c.overlay,
            &OVERLAY_POSITIONS
                .iter()
                .map(|m| m.1.to_string())
                .collect::<Vec<_>>(),
        );
        combo_set(
            c.overlay,
            OVERLAY_POSITIONS
                .iter()
                .position(|m| m.0 == cfg.overlay)
                .unwrap_or(0),
        );
        set_checked(c.sounds, cfg.audio.play_sounds);
        set_checked(c.mute, cfg.audio.mute_system_audio);
        set_checked(c.autostart, autostart::is_enabled());
        let names: Vec<&str> = cfg.modes.iter().map(|m| m.name.as_str()).collect();
        set_text(
            c.modes_label,
            &if names.is_empty() {
                "No modes configured".to_string()
            } else {
                names.join(", ")
            },
        );

        // Transcription
        combo_fill(
            c.t_provider,
            &TranscriptionProvider::ALL
                .iter()
                .map(|p| p.display_name().to_string())
                .collect::<Vec<_>>(),
        );
        combo_set(
            c.t_provider,
            TranscriptionProvider::ALL
                .iter()
                .position(|p| *p == cfg.transcription.provider)
                .unwrap_or(0),
        );
        self.on_transcription_provider(Some(cfg.transcription.model_name()));
        let c = &self.c;
        combo_fill(
            c.t_language,
            &LANGUAGES
                .iter()
                .map(|l| l.1.to_string())
                .collect::<Vec<_>>(),
        );
        combo_set(
            c.t_language,
            LANGUAGES
                .iter()
                .position(|l| l.0.eq_ignore_ascii_case(&cfg.transcription.language))
                .unwrap_or(0),
        );
        set_text(c.t_endpoint, &cfg.transcription.custom_endpoint);
        set_checked(c.t_filter, cfg.transcription.filter_output);
        set_checked(c.t_formatting, cfg.transcription.text_formatting);
        set_text(c.t_fillers, &cfg.filler_words.join(", "));

        // Enhancement
        set_checked(c.e_enabled, cfg.enhancement.enabled);
        combo_fill(
            c.e_provider,
            &EnhancementProvider::ALL
                .iter()
                .map(|p| p.display_name().to_string())
                .collect::<Vec<_>>(),
        );
        combo_set(
            c.e_provider,
            EnhancementProvider::ALL
                .iter()
                .position(|p| *p == cfg.enhancement.provider)
                .unwrap_or(0),
        );
        self.on_enhancement_provider(Some(cfg.enhancement.model_name()));
        let c = &self.c;
        set_checked(c.e_window, cfg.enhancement.use_window_context);
        set_checked(c.e_clipboard, cfg.enhancement.use_clipboard_context);
        set_checked(c.e_selection, cfg.enhancement.use_selected_text_context);
        set_checked(c.e_skip_short, cfg.enhancement.skip_short_transcripts);
        set_text(
            c.e_short_words,
            &cfg.enhancement.short_transcript_word_threshold.to_string(),
        );
        set_text(c.e_timeout, &cfg.enhancement.timeout_secs.to_string());

        // Prompts
        self.prompt_index = cfg
            .prompts
            .iter()
            .position(|p| p.id == cfg.enhancement.prompt_id)
            .unwrap_or(0);
        self.refill_prompts();
        self.show_prompt();

        // Dictionary
        let c = &self.c;
        set_text(c.vocabulary, &cfg.vocabulary.join("\n"));
        set_text(
            c.replacements,
            &cfg.replacements
                .iter()
                .map(|r| format!("{} -> {}", r.original, r.replacement))
                .collect::<Vec<_>>()
                .join("\n"),
        );

        // Snippets
        set_text(
            c.snippets,
            &crate::text::snippets::format_lines(&cfg.snippets),
        );

        // Command Mode
        set_checked(c.c_enabled, cfg.command.enabled);
        set_text(c.c_hotkey, &cfg.command.hotkey);
        let mut providers = vec!["Same as AI Enhancement".to_string()];
        providers.extend(
            EnhancementProvider::ALL
                .iter()
                .map(|p| p.display_name().to_string()),
        );
        combo_fill(c.c_provider, &providers);
        combo_set(
            c.c_provider,
            cfg.command
                .provider
                .and_then(|p| EnhancementProvider::ALL.iter().position(|x| *x == p))
                .map_or(0, |i| i + 1),
        );
        self.on_command_provider(cfg.command.model.clone());
        let c = &self.c;

        // Output
        combo_fill(
            c.o_method,
            &PASTE_METHODS
                .iter()
                .map(|m| m.1.to_string())
                .collect::<Vec<_>>(),
        );
        combo_set(
            c.o_method,
            PASTE_METHODS
                .iter()
                .position(|m| m.0 == cfg.output.method)
                .unwrap_or(0),
        );
        set_checked(c.o_restore, cfg.output.restore_clipboard);
        set_text(
            c.o_restore_delay,
            &cfg.output.clipboard_restore_delay_ms.to_string(),
        );
        combo_fill(
            c.o_send_key,
            &SEND_KEYS
                .iter()
                .map(|m| m.1.to_string())
                .collect::<Vec<_>>(),
        );
        combo_set(
            c.o_send_key,
            SEND_KEYS
                .iter()
                .position(|m| m.0 == cfg.output.send_key)
                .unwrap_or(0),
        );
        set_checked(c.o_space, cfg.output.append_space);

        // History
        set_checked(c.h_enabled, cfg.history.enabled);
        set_checked(c.h_audio, cfg.history.save_audio);
        set_text(c.h_max, &cfg.history.max_entries.to_string());
    }

    fn selected_transcription_provider(&self) -> TranscriptionProvider {
        TranscriptionProvider::ALL[combo_sel(self.c.t_provider)
            .unwrap_or(0)
            .min(TranscriptionProvider::ALL.len() - 1)]
    }

    fn selected_enhancement_provider(&self) -> EnhancementProvider {
        EnhancementProvider::ALL[combo_sel(self.c.e_provider)
            .unwrap_or(0)
            .min(EnhancementProvider::ALL.len() - 1)]
    }

    fn on_transcription_provider(&mut self, model: Option<String>) {
        let p = self.selected_transcription_provider();
        let models = transcription_models(p);
        combo_fill(self.c.t_model, &models);
        set_text(
            self.c.t_model,
            &model.unwrap_or_else(|| p.default_model().to_string()),
        );
        self.update_key_ui();
    }

    fn on_enhancement_provider(&mut self, model: Option<String>) {
        let p = self.selected_enhancement_provider();
        combo_fill(self.c.e_model, &enhancement_models(p));
        set_text(
            self.c.e_model,
            &model.unwrap_or_else(|| p.default_model().to_string()),
        );
        let (label, value, visible) = match p {
            EnhancementProvider::Ollama => (
                "Ollama URL",
                self.config.enhancement.ollama_base_url.clone(),
                true,
            ),
            EnhancementProvider::Custom => (
                "Chat endpoint",
                self.config.enhancement.custom_endpoint.clone(),
                true,
            ),
            _ => ("", String::new(), false),
        };
        set_text(self.c.e_endpoint_label, label);
        set_text(self.c.e_endpoint, &value);
        if self.page == 3 {
            unsafe {
                let _ = ShowWindow(self.c.e_endpoint, if visible { SW_SHOW } else { SW_HIDE });
            }
        }
        self.update_key_ui();
    }

    /// `None` = same provider as AI Enhancement.
    fn selected_command_provider(&self) -> Option<EnhancementProvider> {
        combo_sel(self.c.c_provider)
            .filter(|&i| i > 0)
            .and_then(|i| EnhancementProvider::ALL.get(i - 1).copied())
    }

    fn on_command_provider(&mut self, model: Option<String>) {
        let models = self
            .selected_command_provider()
            .map(enhancement_models)
            .unwrap_or_default();
        combo_fill(self.c.c_model, &models);
        set_text(self.c.c_model, &model.unwrap_or_default());
    }

    fn update_key_ui(&self) {
        let t = self.selected_transcription_provider().key_name();
        set_text(self.c.t_key_status, key_status(t));
        cue(
            self.c.t_key,
            if credentials::has(t) {
                "stored — type to replace"
            } else {
                "paste your API key"
            },
        );
        let e = self.selected_enhancement_provider().key_name();
        set_text(self.c.e_key_status, key_status(e));
        cue(
            self.c.e_key,
            if credentials::has(e) {
                "stored — type to replace"
            } else {
                "paste your API key"
            },
        );
    }

    // -- prompts ------------------------------------------------------------

    fn refill_prompts(&self) {
        let titles: Vec<String> = self
            .config
            .prompts
            .iter()
            .map(|p| p.title.clone())
            .collect();
        combo_fill(self.c.p_select, &titles);
        combo_set(self.c.p_select, self.prompt_index);
        let active = combo_sel(self.c.e_prompt)
            .and_then(|i| self.config.prompts.get(i))
            .map(|p| p.id.clone())
            .unwrap_or_else(|| self.config.enhancement.prompt_id.clone());
        combo_fill(self.c.e_prompt, &titles);
        combo_set(
            self.c.e_prompt,
            self.config
                .prompts
                .iter()
                .position(|p| p.id == active)
                .unwrap_or(0),
        );
    }

    fn show_prompt(&self) {
        if let Some(p) = self.config.prompts.get(self.prompt_index) {
            set_text(self.c.p_title, &p.title);
            set_checked(self.c.p_system, p.use_system_instructions);
            set_text(self.c.p_text, &p.prompt_text);
        }
    }

    /// Copies the prompt editor back into the working config.
    fn store_prompt(&mut self) {
        let title = get_text(self.c.p_title).trim().to_string();
        let text = get_text(self.c.p_text).replace("\r\n", "\n");
        let system = is_checked(self.c.p_system);
        if let Some(p) = self.config.prompts.get_mut(self.prompt_index) {
            if !title.is_empty() {
                p.title = title;
            }
            p.prompt_text = text;
            p.use_system_instructions = system;
        }
    }

    // -- save ---------------------------------------------------------------

    fn collect(&mut self) -> Result<Config, String> {
        self.store_prompt();
        let c = &self.c;
        let mut cfg = self.config.clone();
        let number = |h: HWND, what: &str| -> Result<u64, String> {
            get_text(h)
                .trim()
                .parse::<u64>()
                .map_err(|_| format!("{what} must be a number"))
        };

        // General
        let record = get_text(c.hk_record).trim().to_string();
        parse_hotkey(&record).map_err(|e| format!("Record shortcut: {e}"))?;
        cfg.hotkeys.record = record;
        cfg.hotkeys.mode = HOTKEY_MODES[combo_sel(c.hk_mode).unwrap_or(0)].0;
        cfg.hotkeys.hybrid_threshold_ms =
            number(c.hk_threshold, "Hold threshold")?.clamp(100, 5000);
        let cancel = get_text(c.hk_cancel).trim().to_string();
        if !cancel.is_empty() {
            parse_hotkey(&cancel).map_err(|e| format!("Cancel shortcut: {e}"))?;
        }
        cfg.hotkeys.cancel = cancel;
        let paste_last = get_text(c.hk_paste_last).trim().to_string();
        if !paste_last.is_empty() {
            parse_hotkey(&paste_last).map_err(|e| format!("Paste-last shortcut: {e}"))?;
        }
        cfg.hotkeys.paste_last = (!paste_last.is_empty()).then_some(paste_last);
        cfg.audio.input_device = match combo_sel(c.microphone) {
            Some(0) | None => None,
            Some(_) => Some(get_text(c.microphone)),
        };
        cfg.overlay = OVERLAY_POSITIONS[combo_sel(c.overlay).unwrap_or(0)].0;
        cfg.audio.play_sounds = is_checked(c.sounds);
        cfg.audio.mute_system_audio = is_checked(c.mute);
        cfg.start_with_windows = is_checked(c.autostart);

        // Transcription
        let tp = self.selected_transcription_provider();
        if tp != cfg.transcription.provider {
            cfg.transcription.model = None;
        }
        cfg.transcription.provider = tp;
        let model = get_text(c.t_model).trim().to_string();
        cfg.transcription.model =
            (!model.is_empty() && model != tp.default_model()).then_some(model);
        cfg.transcription.language = LANGUAGES[combo_sel(c.t_language).unwrap_or(0)]
            .0
            .to_string();
        cfg.transcription.custom_endpoint = get_text(c.t_endpoint).trim().to_string();
        cfg.transcription.filter_output = is_checked(c.t_filter);
        cfg.transcription.text_formatting = is_checked(c.t_formatting);
        cfg.filler_words = get_text(c.t_fillers)
            .split(',')
            .map(|w| w.trim().to_lowercase())
            .filter(|w| !w.is_empty())
            .collect();

        // Enhancement
        let ep = self.selected_enhancement_provider();
        cfg.enhancement.enabled = is_checked(c.e_enabled);
        cfg.enhancement.provider = ep;
        let model = get_text(c.e_model).trim().to_string();
        cfg.enhancement.model = (!model.is_empty() && model != ep.default_model()).then_some(model);
        if let Some(p) = combo_sel(c.e_prompt).and_then(|i| cfg.prompts.get(i)) {
            cfg.enhancement.prompt_id = p.id.clone();
        }
        match ep {
            EnhancementProvider::Ollama => {
                cfg.enhancement.ollama_base_url = get_text(c.e_endpoint).trim().to_string()
            }
            EnhancementProvider::Custom => {
                cfg.enhancement.custom_endpoint = get_text(c.e_endpoint).trim().to_string()
            }
            _ => {}
        }
        cfg.enhancement.use_window_context = is_checked(c.e_window);
        cfg.enhancement.use_clipboard_context = is_checked(c.e_clipboard);
        cfg.enhancement.use_selected_text_context = is_checked(c.e_selection);
        cfg.enhancement.skip_short_transcripts = is_checked(c.e_skip_short);
        cfg.enhancement.short_transcript_word_threshold =
            number(c.e_short_words, "Short dictation words")? as usize;
        cfg.enhancement.timeout_secs = number(c.e_timeout, "Timeout")?.clamp(5, 600);

        // Dictionary
        cfg.vocabulary = get_text(c.vocabulary)
            .lines()
            .map(str::trim)
            .filter(|l| !l.is_empty())
            .map(str::to_string)
            .collect();
        cfg.replacements = parse_replacements(&get_text(c.replacements))?;

        // Snippets
        cfg.snippets = crate::text::snippets::parse_lines(&get_text(c.snippets))?;

        // Command Mode
        cfg.command.enabled = is_checked(c.c_enabled);
        let command_hotkey = get_text(c.c_hotkey).trim().to_string();
        if cfg.command.enabled {
            parse_hotkey(&command_hotkey).map_err(|e| format!("Command shortcut: {e}"))?;
            if command_hotkey.eq_ignore_ascii_case(&cfg.hotkeys.record) {
                return Err("The Command shortcut must differ from the record shortcut".into());
            }
        }
        cfg.command.hotkey = command_hotkey;
        cfg.command.provider = self.selected_command_provider();
        let model = get_text(c.c_model).trim().to_string();
        cfg.command.model = (!model.is_empty()).then_some(model);

        // Output
        cfg.output.method = PASTE_METHODS[combo_sel(c.o_method).unwrap_or(0)].0;
        cfg.output.restore_clipboard = is_checked(c.o_restore);
        cfg.output.clipboard_restore_delay_ms = number(c.o_restore_delay, "Restore delay")?;
        cfg.output.send_key = SEND_KEYS[combo_sel(c.o_send_key).unwrap_or(0)].0;
        cfg.output.append_space = is_checked(c.o_space);

        // History
        cfg.history.enabled = is_checked(c.h_enabled);
        cfg.history.save_audio = is_checked(c.h_audio);
        cfg.history.max_entries = number(c.h_max, "History size")? as usize;
        Ok(cfg)
    }

    fn save(&mut self) {
        let cfg = match self.collect() {
            Ok(cfg) => cfg,
            Err(e) => return message(self.hwnd, &e, true),
        };
        // Reload from disk first so edits made via the tray menu meanwhile aren't lost
        // for settings this window does not show (modes).
        let mut merged = cfg;
        if let Ok(disk) = Config::load(&config::config_path()) {
            merged.modes = disk.modes;
        }
        if let Err(e) = merged.save(&config::config_path()) {
            return message(self.hwnd, &format!("Could not save settings: {e}"), true);
        }
        let mut problems = Vec::new();
        for (edit, name) in [
            (
                self.c.t_key,
                self.selected_transcription_provider().key_name(),
            ),
            (
                self.c.e_key,
                self.selected_enhancement_provider().key_name(),
            ),
        ] {
            let key = get_text(edit).trim().to_string();
            if !key.is_empty() && !name.is_empty() {
                if let Err(e) = credentials::set(name, &key) {
                    problems.push(e);
                }
                set_text(edit, "");
            }
        }
        if merged.start_with_windows != autostart::is_enabled() {
            if let Err(e) = autostart::set_enabled(merged.start_with_windows) {
                problems.push(format!("autostart: {e}"));
            }
        }
        self.config = merged;
        self.update_key_ui();
        unsafe {
            let _ = PostMessageW(Some(self.owner), WM_SETTINGS_SAVED, WPARAM(0), LPARAM(0));
        }
        if problems.is_empty() {
            set_text(self.c.status, "Settings saved.");
        } else {
            message(self.hwnd, &problems.join("\n"), true);
        }
    }

    // -- pages & dashboard --------------------------------------------------

    fn show_page(&mut self, page: usize) {
        if page != self.page && self.page == 4 {
            self.store_prompt();
        }
        self.page = page.min(self.pages.len() - 1);
        if self.page == 3 || self.page == 4 {
            self.refill_prompts();
            if self.page == 4 {
                self.show_prompt();
            }
        }
        for (i, controls) in self.pages.iter().enumerate() {
            for &h in controls {
                unsafe {
                    let _ = ShowWindow(h, if i == self.page { SW_SHOW } else { SW_HIDE });
                }
            }
        }
        if self.page == 3 {
            let custom = matches!(
                self.selected_enhancement_provider(),
                EnhancementProvider::Ollama | EnhancementProvider::Custom
            );
            unsafe {
                let _ = ShowWindow(self.c.e_endpoint, if custom { SW_SHOW } else { SW_HIDE });
            }
        }
        if self.page == 0 {
            self.refresh_dashboard();
        }
        send(self.nav, LB_SETCURSEL, self.page, 0);
        set_text(self.c.status, "");
    }

    fn refresh_dashboard(&mut self) {
        let entries = history::load(&history::history_path());
        STATS.with(|s| *s.borrow_mut() = stats::compute_now(&entries, 14));
        self.recent = entries
            .into_iter()
            .rev()
            .filter(|e| e.status == Status::Completed)
            .take(100)
            .collect();
        send(self.c.recent, LB_RESETCONTENT, 0, 0);
        for e in &self.recent {
            let text: String = e
                .final_text()
                .replace(['\r', '\n'], " ")
                .chars()
                .take(140)
                .collect();
            let line = format!(
                "{}   {}   {}",
                e.timestamp.format("%b %d  %H:%M"),
                e.app.as_deref().unwrap_or("—"),
                text
            );
            let w = wide(&line);
            send(self.c.recent, LB_ADDSTRING, 0, w.as_ptr() as isize);
        }
        unsafe {
            let _ = InvalidateRect(Some(self.c.stats_panel), None, false);
        }
    }

    fn on_command(&mut self, id: usize, code: u32) {
        match (id, code) {
            (ID_NAV, LBN_SELCHANGE) => {
                let sel = send(self.nav, LB_GETCURSEL, 0, 0);
                if sel >= 0 {
                    self.show_page(sel as usize);
                }
            }
            (ID_SAVE, _) => self.save(),
            (ID_CLOSE, _) => unsafe {
                let _ = DestroyWindow(self.hwnd);
            },
            (ID_T_PROVIDER, CBN_SELCHANGE) => self.on_transcription_provider(None),
            (ID_E_PROVIDER, CBN_SELCHANGE) => self.on_enhancement_provider(None),
            (ID_C_PROVIDER, CBN_SELCHANGE) => self.on_command_provider(None),
            (ID_T_REMOVE_KEY, _) | (ID_E_REMOVE_KEY, _) => {
                let name = if id == ID_T_REMOVE_KEY {
                    self.selected_transcription_provider().key_name()
                } else {
                    self.selected_enhancement_provider().key_name()
                };
                if !name.is_empty() {
                    let _ = credentials::remove(name);
                    set_text(self.c.status, &format!("Removed the {name} API key"));
                }
                self.update_key_ui();
            }
            (ID_P_SELECT, CBN_SELCHANGE) => {
                self.store_prompt();
                self.prompt_index = combo_sel(self.c.p_select).unwrap_or(0);
                self.refill_prompts();
                self.show_prompt();
            }
            (ID_P_NEW, _) => {
                self.store_prompt();
                self.config.prompts.push(CustomPrompt {
                    id: uuid::Uuid::new_v4().to_string().to_uppercase(),
                    title: "New prompt".into(),
                    prompt_text:
                        "<TASK>\nDescribe how the transcript should be rewritten.\n</TASK>".into(),
                    use_system_instructions: true,
                });
                self.prompt_index = self.config.prompts.len() - 1;
                self.refill_prompts();
                self.show_prompt();
            }
            (ID_P_DELETE, _) => {
                if self.config.prompts.len() <= 1 {
                    return message(self.hwnd, "At least one prompt is required.", false);
                }
                self.config.prompts.remove(self.prompt_index);
                self.prompt_index = self.prompt_index.min(self.config.prompts.len() - 1);
                self.refill_prompts();
                self.show_prompt();
            }
            (ID_RECENT, LBN_DBLCLK) => {
                let sel = send(self.c.recent, LB_GETCURSEL, 0, 0);
                if let Some(e) = (sel >= 0).then(|| self.recent.get(sel as usize)).flatten() {
                    match clipboard::set_text(e.final_text(), false) {
                        Ok(_) => set_text(self.c.status, "Copied to the clipboard"),
                        Err(err) => set_text(self.c.status, &err),
                    }
                }
            }
            (ID_REFRESH, _) => self.refresh_dashboard(),
            (ID_EXPORT, _) => {
                let out = config::data_dir().join("history.csv");
                let entries = history::load(&history::history_path());
                match std::fs::File::create(&out)
                    .and_then(|mut f| history::export_csv(&entries, &mut f))
                {
                    Ok(()) => open_path(&out),
                    Err(e) => message(self.hwnd, &e.to_string(), true),
                }
            }
            (ID_OPEN_FOLDER, _) => open_path(&config::data_dir()),
            (ID_EDIT_MODES, _) => open_path(&config::config_path()),
            (ID_CLEAR_HISTORY, _) => {
                let answer = unsafe {
                    MessageBoxW(
                        Some(self.hwnd),
                        w!("Delete all transcriptions and saved recordings? This cannot be undone."),
                        w!("VoiceInk"),
                        MB_YESNO | MB_ICONWARNING,
                    )
                };
                if answer == IDYES {
                    let _ = std::fs::remove_file(history::history_path());
                    let _ = std::fs::remove_dir_all(history::recordings_dir());
                    self.refresh_dashboard();
                    set_text(self.c.status, "History deleted");
                }
            }
            _ => {}
        }
    }
}

fn open_path(path: &std::path::Path) {
    let p = wide(&path.to_string_lossy());
    unsafe {
        windows::Win32::UI::Shell::ShellExecuteW(
            None,
            w!("open"),
            PCWSTR(p.as_ptr()),
            None,
            None,
            SW_SHOWNORMAL,
        );
    }
}

// ---------------------------------------------------------------------------
// Stats panel painting
// ---------------------------------------------------------------------------

fn rgb(r: u8, g: u8, b: u8) -> COLORREF {
    COLORREF(r as u32 | (g as u32) << 8 | (b as u32) << 16)
}

unsafe fn draw_text(dc: HDC, text: &str, rect: RECT, font: HFONT, color: COLORREF, flags: u32) {
    let mut r = rect;
    let mut w: Vec<u16> = text.encode_utf16().collect();
    let old = SelectObject(dc, HGDIOBJ(font.0));
    SetTextColor(dc, color);
    DrawTextW(
        dc,
        &mut w,
        &mut r,
        windows::Win32::Graphics::Gdi::DRAW_TEXT_FORMAT(flags),
    );
    SelectObject(dc, old);
}

unsafe fn fill_round(dc: HDC, r: RECT, radius: i32, color: COLORREF) {
    let brush = CreateSolidBrush(color);
    let old_brush = SelectObject(dc, HGDIOBJ(brush.0));
    let old_pen = SelectObject(dc, GetStockObject(NULL_PEN));
    let _ = RoundRect(dc, r.left, r.top, r.right + 1, r.bottom + 1, radius, radius);
    SelectObject(dc, old_pen);
    SelectObject(dc, old_brush);
    let _ = DeleteObject(HGDIOBJ(brush.0));
}

unsafe fn paint_stats(hwnd: HWND) {
    let mut ps = PAINTSTRUCT::default();
    let hdc = BeginPaint(hwnd, &mut ps);
    let mut rc = RECT::default();
    let _ = GetClientRect(hwnd, &mut rc);
    let (w, h) = (rc.right, rc.bottom);
    let mem = CreateCompatibleDC(Some(hdc));
    let bmp = CreateCompatibleBitmap(hdc, w, h);
    let old_bmp = SelectObject(mem, HGDIOBJ(bmp.0));
    FillRect(mem, &rc, GetSysColorBrush(COLOR_WINDOW));
    SetBkMode(mem, TRANSPARENT);

    let scale = GetDpiForWindow(hwnd) as f32 / 96.0;
    let px = |v: f32| (v * scale).round() as i32;
    let (font, title_font, big_font) = FONTS.with(|f| *f.borrow());
    let muted = rgb(0x6B, 0x72, 0x80);
    let ink = rgb(0x11, 0x18, 0x27);
    let accent = rgb(0x25, 0x63, 0xEB);
    let tile_bg = rgb(0xF3, 0xF4, 0xF6);
    let flags_l = (DT_LEFT | DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS).0;
    let flags_c = (DT_CENTER | DT_SINGLELINE | DT_VCENTER).0;

    STATS.with(|s| {
        let s = s.borrow();
        // Tiles.
        let tiles = [
            (
                "Words dictated",
                stats::format_count(s.words),
                format!("{} sessions", stats::format_count(s.sessions)),
            ),
            (
                "Time saved",
                stats::format_duration(s.time_saved_secs),
                format!("vs typing at {} WPM", stats::TYPING_WPM),
            ),
            (
                "Speaking speed",
                format!("{:.0} WPM", s.wpm),
                format!("{} recorded", stats::format_duration(s.duration_secs)),
            ),
            (
                "Streak",
                format!(
                    "{} day{}",
                    s.streak_days,
                    if s.streak_days == 1 { "" } else { "s" }
                ),
                format!("{} AI-enhanced", stats::format_count(s.enhanced_sessions)),
            ),
        ];
        let gap = px(12.0);
        let tile_w = (w - gap * 3) / 4;
        let tile_h = px(92.0);
        for (i, (label, value, sub)) in tiles.iter().enumerate() {
            let x = i as i32 * (tile_w + gap);
            let r = RECT {
                left: x,
                top: 0,
                right: x + tile_w,
                bottom: tile_h,
            };
            fill_round(mem, r, px(12.0), tile_bg);
            let inner = |top: f32, height: f32| RECT {
                left: x + px(14.0),
                top: px(top),
                right: x + tile_w - px(10.0),
                bottom: px(top + height),
            };
            draw_text(mem, label, inner(8.0, 22.0), font, muted, flags_l);
            draw_text(
                mem,
                value,
                inner(30.0, 34.0),
                big_font,
                if i == 1 { accent } else { ink },
                flags_l,
            );
            draw_text(mem, sub, inner(64.0, 20.0), font, muted, flags_l);
        }

        // Activity chart: words per day, last 14 days.
        let top = tile_h + px(16.0);
        let chart_w = (w as f32 * 0.64) as i32;
        let chart = RECT {
            left: 0,
            top,
            right: chart_w,
            bottom: h,
        };
        fill_round(mem, chart, px(12.0), tile_bg);
        draw_text(
            mem,
            "Words per day — last 14 days",
            RECT {
                left: px(14.0),
                top: top + px(6.0),
                right: chart_w,
                bottom: top + px(30.0),
            },
            title_font,
            ink,
            flags_l,
        );
        let max = s.daily_words.iter().map(|d| d.1).max().unwrap_or(0).max(1);
        let n = s.daily_words.len().max(1) as i32;
        let plot_l = px(14.0);
        let plot_r = chart_w - px(14.0);
        let plot_t = top + px(40.0);
        let plot_b = h - px(26.0);
        let slot = (plot_r - plot_l) / n;
        let bar_w = (slot as f32 * 0.6) as i32;
        for (i, (date, words)) in s.daily_words.iter().enumerate() {
            let x = plot_l + i as i32 * slot + (slot - bar_w) / 2;
            let bh = ((*words as f32 / max as f32) * (plot_b - plot_t) as f32) as i32;
            let bar = RECT {
                left: x,
                top: plot_b - bh.max(px(2.0)),
                right: x + bar_w,
                bottom: plot_b,
            };
            fill_round(
                mem,
                bar,
                px(4.0),
                if *words > 0 {
                    accent
                } else {
                    rgb(0xD1, 0xD5, 0xDB)
                },
            );
            if i % 2 == (s.daily_words.len() + 1) % 2 || i + 1 == s.daily_words.len() {
                draw_text(
                    mem,
                    &date.format("%d").to_string(),
                    RECT {
                        left: x - px(8.0),
                        top: plot_b + px(4.0),
                        right: x + bar_w + px(8.0),
                        bottom: h - px(4.0),
                    },
                    font,
                    muted,
                    flags_c,
                );
            }
        }

        // Top apps.
        let apps = RECT {
            left: chart_w + gap,
            top,
            right: w,
            bottom: h,
        };
        fill_round(mem, apps, px(12.0), tile_bg);
        draw_text(
            mem,
            "Top apps",
            RECT {
                left: apps.left + px(14.0),
                top: top + px(6.0),
                right: w,
                bottom: top + px(30.0),
            },
            title_font,
            ink,
            flags_l,
        );
        if s.top_apps.is_empty() {
            draw_text(
                mem,
                "Dictate something to see stats",
                RECT {
                    left: apps.left + px(14.0),
                    top: top + px(40.0),
                    right: w - px(10.0),
                    bottom: top + px(64.0),
                },
                font,
                muted,
                flags_l,
            );
        }
        for (i, (app, count)) in s.top_apps.iter().enumerate() {
            let y = top + px(40.0 + i as f32 * 26.0);
            let row = |l: i32, r: i32| RECT {
                left: l,
                top: y,
                right: r,
                bottom: y + px(24.0),
            };
            draw_text(
                mem,
                app.trim_end_matches(".exe"),
                row(apps.left + px(14.0), w - px(60.0)),
                font,
                ink,
                flags_l,
            );
            draw_text(
                mem,
                &count.to_string(),
                row(w - px(56.0), w - px(14.0)),
                font,
                muted,
                flags_c,
            );
        }
    });

    let _ = BitBlt(hdc, 0, 0, w, h, Some(mem), 0, 0, SRCCOPY);
    SelectObject(mem, old_bmp);
    let _ = DeleteObject(HGDIOBJ(bmp.0));
    let _ = DeleteDC(mem);
    let _ = EndPaint(hwnd, &ps);
}

unsafe extern "system" fn stats_proc(
    hwnd: HWND,
    msg: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    if msg == WM_PAINT {
        paint_stats(hwnd);
        return LRESULT(0);
    }
    DefWindowProcW(hwnd, msg, wparam, lparam)
}

// ---------------------------------------------------------------------------
// Window
// ---------------------------------------------------------------------------

fn with_ui<R>(f: impl FnOnce(&mut Ui) -> R) -> Option<R> {
    UI.with(|u| {
        let mut guard = u.try_borrow_mut().ok()?;
        guard.as_mut().map(f)
    })
}

unsafe extern "system" fn wnd_proc(
    hwnd: HWND,
    msg: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    match msg {
        WM_COMMAND => {
            let id = wparam.0 & 0xFFFF;
            let code = ((wparam.0 >> 16) & 0xFFFF) as u32;
            with_ui(|ui| ui.on_command(id, code));
            LRESULT(0)
        }
        WM_CTLCOLORSTATIC => {
            // Labels and check boxes on the white window background.
            let brush: HBRUSH = GetSysColorBrush(COLOR_WINDOW);
            LRESULT(brush.0 as isize)
        }
        WM_CLOSE => {
            let _ = DestroyWindow(hwnd);
            LRESULT(0)
        }
        WM_DESTROY => {
            UI.with(|u| {
                if let Ok(mut guard) = u.try_borrow_mut() {
                    if let Some(ui) = guard.take() {
                        let _ = DeleteObject(HGDIOBJ(ui.font.0));
                        let _ = DeleteObject(HGDIOBJ(ui.title_font.0));
                    }
                }
            });
            FONTS.with(|f| {
                let (a, b, c) = std::mem::take(&mut *f.borrow_mut());
                for font in [a, b, c] {
                    let _ = DeleteObject(HGDIOBJ(font.0));
                }
            });
            LRESULT(0)
        }
        _ => DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}

/// The open settings window, for `IsDialogMessageW` keyboard handling.
pub fn hwnd() -> Option<HWND> {
    UI.with(|u| {
        u.try_borrow()
            .ok()
            .and_then(|g| g.as_ref().map(|ui| ui.hwnd))
    })
}

/// Re-reads history after a dictation, if the dashboard is open.
pub fn refresh() {
    with_ui(|ui| {
        if ui.page == 0 {
            ui.refresh_dashboard();
        }
    });
}

/// Opens the window on `page` (0 = Dashboard), or focuses it if already open.
pub fn open(owner: HWND, page: usize) -> Result<(), String> {
    if let Some(existing) = hwnd() {
        unsafe {
            if IsWindow(Some(existing)).as_bool() {
                with_ui(|ui| ui.show_page(page));
                let _ = ShowWindow(existing, SW_SHOWNORMAL);
                let _ = SetForegroundWindow(existing);
                return Ok(());
            }
        }
    }

    let config = Config::load(&config::config_path())?;
    let devices = capture::list_input_devices()
        .map(|d| d.into_iter().map(|(name, _)| name).collect())
        .unwrap_or_default();

    unsafe {
        let instance = GetModuleHandleW(None).map_err(|e| e.to_string())?;
        let class = w!("VoiceInkSettings");
        RegisterClassW(&WNDCLASSW {
            lpfnWndProc: Some(wnd_proc),
            hInstance: instance.into(),
            lpszClassName: class,
            hCursor: LoadCursorW(None, IDC_ARROW).unwrap_or_default(),
            hbrBackground: GetSysColorBrush(COLOR_WINDOW),
            ..Default::default()
        });
        RegisterClassW(&WNDCLASSW {
            lpfnWndProc: Some(stats_proc),
            hInstance: instance.into(),
            lpszClassName: w!("VoiceInkStatsPanel"),
            hCursor: LoadCursorW(None, IDC_ARROW).unwrap_or_default(),
            ..Default::default()
        });

        let style = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX;
        let hwnd = CreateWindowExW(
            WS_EX_CONTROLPARENT,
            class,
            w!("VoiceInk — Dashboard & Settings"),
            style,
            CW_USEDEFAULT,
            CW_USEDEFAULT,
            CLIENT_W,
            CLIENT_H,
            None,
            None,
            Some(instance.into()),
            None,
        )
        .map_err(|e| format!("settings window: {e}"))?;

        // Size the window for the monitor's DPI.
        let scale = GetDpiForWindow(hwnd) as f32 / 96.0;
        let mut rect = RECT {
            left: 0,
            top: 0,
            right: (CLIENT_W as f32 * scale) as i32,
            bottom: (CLIENT_H as f32 * scale) as i32,
        };
        let _ = AdjustWindowRectEx(&mut rect, style, false, WS_EX_CONTROLPARENT);
        let _ = SetWindowPos(
            hwnd,
            None,
            0,
            0,
            rect.right - rect.left,
            rect.bottom - rect.top,
            SWP_NOMOVE | SWP_NOZORDER,
        );
        for (size, kind) in [(32usize, ICON_BIG), (16, ICON_SMALL)] {
            if let Some(icon) = create_icon(size, IconState::Idle) {
                SendMessageW(
                    hwnd,
                    WM_SETICON,
                    Some(WPARAM(kind as usize)),
                    Some(LPARAM(icon.0 as isize)),
                );
            }
        }

        let font = make_font(scale, 9.5, FW_NORMAL);
        let title_font = make_font(scale, 15.0, FW_SEMIBOLD);
        FONTS.with(|f| {
            *f.borrow_mut() = (
                make_font(scale, 9.0, FW_NORMAL),
                make_font(scale, 10.5, FW_SEMIBOLD),
                make_font(scale, 18.0, FW_BOLD),
            )
        });

        let mut ui = Ui {
            hwnd,
            owner,
            scale,
            font,
            title_font,
            nav: HWND::default(),
            pages: Vec::new(),
            page: usize::MAX,
            config,
            c: Controls::default(),
            prompt_index: 0,
            devices,
            recent: Vec::new(),
        };
        build(&mut ui);
        ui.load();
        UI.with(|u| *u.borrow_mut() = Some(ui));
        with_ui(|ui| ui.show_page(page));

        let _ = ShowWindow(hwnd, SW_SHOWNORMAL);
        let _ = SetForegroundWindow(hwnd);
    }
    Ok(())
}
