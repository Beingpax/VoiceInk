//! Dashboard & Settings window — the Windows counterpart of the macOS
//! dashboard and settings views, built from standard Win32 controls.
//!
//! The window edits a working copy of the configuration. Each page is its
//! own type (see [`pages`]); **Save** lets every page validate and apply its
//! fields, writes `config.json`, stores typed API keys and posts
//! [`WM_SETTINGS_SAVED`] so the app reloads hotkeys and options.

mod pages;
mod stats_panel;
mod widgets;

use super::error::{Context, Result};
use super::gdi;
use super::icon::{IconState, OwnedIcon, create_icon};
use crate::config::Config;
use crate::context::AppContext;
use crate::settings_page::SettingsPage;
use pages::{KeyChanges, Page, PageContext};
use std::cell::RefCell;
use widgets::{Builder, CLIENT_H, CLIENT_W, LBN_SELCHANGE, LEFT, Label, ListBox, Severity, message_box, set_visible};
use windows::Win32::Foundation::{HWND, LPARAM, LRESULT, RECT, WPARAM};
use windows::Win32::Graphics::Gdi::{COLOR_WINDOW, FW_NORMAL, FW_SEMIBOLD, GetSysColorBrush};
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::UI::HiDpi::GetDpiForWindow;
use windows::Win32::UI::WindowsAndMessaging::{
    AdjustWindowRectEx, CW_USEDEFAULT, CreateWindowExW, DefWindowProcW, DestroyWindow, ICON_BIG, ICON_SMALL, IDC_ARROW,
    IsWindow, LoadCursorW, PostMessageW, RegisterClassW, SW_SHOWNORMAL, SWP_NOMOVE, SWP_NOZORDER, SendMessageW,
    SetForegroundWindow, SetWindowPos, ShowWindow, WM_APP, WM_CLOSE, WM_COMMAND, WM_CTLCOLORSTATIC, WM_DESTROY,
    WM_SETICON, WNDCLASSW, WS_CAPTION, WS_EX_CONTROLPARENT, WS_MINIMIZEBOX, WS_OVERLAPPED, WS_SYSMENU,
};
use windows::core::w;

/// Posted to the owner (the app window) after the settings were written.
pub const WM_SETTINGS_SAVED: u32 = WM_APP + 8;

const ID_NAV: u16 = 1;
const ID_SAVE: u16 = 2;
const ID_CLOSE: u16 = 3;
/// Page controls get ids `PAGE_ID_BASE + page * PAGE_ID_STRIDE + local id`.
const PAGE_ID_BASE: u16 = 1000;
const PAGE_ID_STRIDE: u16 = 100;
const BASE_DPI: f32 = 96.0;
const FONT_POINTS: f32 = 9.5;
const TITLE_POINTS: f32 = 15.0;

/// A page and the controls it created (shown and hidden together).
struct PageSlot {
    page: Box<dyn Page>,
    controls: Vec<HWND>,
}

struct SettingsWindow {
    hwnd: HWND,
    owner: HWND,
    ctx: AppContext,
    nav: ListBox,
    status: Label,
    pages: Vec<PageSlot>,
    current: Option<SettingsPage>,
    /// The configuration as edited so far (applied to disk on Save).
    working: Config,
    // Kept alive while the window uses them.
    _fonts: [gdi::Owned; 2],
    _icons: Vec<OwnedIcon>,
}

thread_local! {
    static WINDOW: RefCell<Option<SettingsWindow>> = const { RefCell::new(None) };
}

/// Runs `f` on the open window; `None` when closed or already in use
/// (re-entered from a nested message loop such as a message box).
fn with_window<R>(f: impl FnOnce(&mut SettingsWindow) -> R) -> Option<R> {
    WINDOW.with(|w| w.try_borrow_mut().ok()?.as_mut().map(f))
}

/// Splits a `WM_COMMAND` control id into page and page-relative id.
fn page_of(id: u16) -> Option<(SettingsPage, u16)> {
    let offset = id.checked_sub(PAGE_ID_BASE)?;
    let page = SettingsPage::from_index(usize::from(offset / PAGE_ID_STRIDE))?;
    Some((page, offset % PAGE_ID_STRIDE))
}

impl SettingsWindow {
    /// Runs `f` on one page with the context it may use.
    fn on_page<R>(
        &mut self,
        page: SettingsPage,
        f: impl FnOnce(&mut dyn Page, &mut Config, &PageContext<'_>) -> R,
    ) -> R {
        let cx = PageContext { app: &self.ctx, window: self.hwnd, status: self.status };
        f(self.pages[page.index()].page.as_mut(), &mut self.working, &cx)
    }

    fn show_page(&mut self, page: SettingsPage) {
        if self.current == Some(page) {
            return;
        }
        if let Some(previous) = self.current {
            self.on_page(previous, |p, config, _| p.leave(config));
            self.pages[previous.index()].controls.iter().for_each(|&c| set_visible(c, false));
        }
        self.pages[page.index()].controls.iter().for_each(|&c| set_visible(c, true));
        self.current = Some(page);
        self.on_page(page, |p, config, cx| p.enter(config, cx));
        self.nav.select(page.index());
        self.status.set("");
    }

    fn command(&mut self, id: u16, code: u32) -> Option<Close> {
        match (id, code) {
            (ID_NAV, LBN_SELCHANGE) => {
                if let Some(page) = self.nav.selected().and_then(SettingsPage::from_index) {
                    self.show_page(page);
                }
            }
            (ID_SAVE, _) => self.save(),
            (ID_CLOSE, _) => return Some(Close),
            _ => {
                if let Some((page, local)) = page_of(id) {
                    self.on_page(page, |p, config, cx| p.command(local, code, config, cx));
                }
            }
        }
        None
    }

    /// Lets every page apply its fields to a copy of the working configuration.
    fn collect(&mut self) -> std::result::Result<(Config, KeyChanges), (SettingsPage, String)> {
        if let Some(current) = self.current {
            self.on_page(current, |p, config, _| p.leave(config));
        }
        let mut config = self.working.clone();
        let mut keys = KeyChanges::new();
        for page in SettingsPage::ALL {
            self.pages[page.index()].page.apply(&mut config, &mut keys).map_err(|message| (page, message))?;
        }
        // Modes have no page; keep hand edits made while the window was open.
        if let Ok(disk) = self.ctx.load_config() {
            config.modes = disk.modes;
        }
        Ok((config, keys))
    }

    fn save(&mut self) {
        let (config, keys) = match self.collect() {
            Ok(collected) => collected,
            Err((page, message)) => {
                self.show_page(page);
                return message_box(self.hwnd, &message, Severity::Error);
            }
        };
        if let Err(e) = config.save(&self.ctx.paths.config()) {
            return message_box(self.hwnd, &format!("Could not save settings: {e}"), Severity::Error);
        }
        let problems: Vec<String> = keys
            .iter()
            .filter_map(|(name, key)| self.ctx.secrets.set(name, key).err().map(|e| format!("{name}: {e}")))
            .collect();
        self.working = config;
        for page in SettingsPage::ALL {
            self.on_page(page, |p, _, cx| p.saved(cx));
        }
        // SAFETY: posting to the app window; a closed owner just drops the message.
        let _ = unsafe { PostMessageW(Some(self.owner), WM_SETTINGS_SAVED, WPARAM(0), LPARAM(0)) };
        if problems.is_empty() {
            self.status.set("Settings saved.");
        } else {
            message_box(self.hwnd, &format!("Some API keys were not saved:\n{}", problems.join("\n")), Severity::Error);
        }
    }

    fn history_changed(&mut self) {
        if let Some(page) = self.current {
            self.on_page(page, |p, _, cx| p.history_changed(cx));
        }
    }
}

/// The user asked to close the window (handled outside the state borrow).
struct Close;

unsafe extern "system" fn wnd_proc(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    match msg {
        WM_COMMAND => {
            let id = (wparam.0 & 0xFFFF) as u16;
            let code = ((wparam.0 >> 16) & 0xFFFF) as u32;
            if with_window(|w| w.command(id, code)).flatten().is_some() {
                // SAFETY: our own window.
                let _ = unsafe { DestroyWindow(hwnd) };
            }
            LRESULT(0)
        }
        // Labels and check boxes on the white window background.
        // SAFETY: system brushes need no cleanup.
        WM_CTLCOLORSTATIC => LRESULT(unsafe { GetSysColorBrush(COLOR_WINDOW) }.0 as isize),
        WM_CLOSE => {
            // SAFETY: our own window.
            let _ = unsafe { DestroyWindow(hwnd) };
            LRESULT(0)
        }
        WM_DESTROY => {
            WINDOW.with(|w| w.try_borrow_mut().map(|mut state| state.take()).ok());
            LRESULT(0)
        }
        // SAFETY: default handling for everything else.
        _ => unsafe { DefWindowProcW(hwnd, msg, wparam, lparam) },
    }
}

/// The open settings window, for `IsDialogMessageW` keyboard navigation.
pub fn dialog_hwnd() -> Option<HWND> {
    WINDOW.with(|w| w.try_borrow().ok()?.as_ref().map(|s| s.hwnd))
}

/// Refreshes the dashboard after a dictation, if the window is open.
pub fn history_changed() {
    with_window(SettingsWindow::history_changed);
}

/// Opens the window on `page`, or brings the open window forward.
///
/// # Errors
/// Fails when the configuration cannot be read or the window cannot be created.
pub fn open(owner: HWND, ctx: &AppContext, page: SettingsPage) -> Result<()> {
    if let Some(existing) = dialog_hwnd() {
        // SAFETY: the handle is validated with IsWindow first.
        if unsafe { IsWindow(Some(existing)) }.as_bool() {
            with_window(|w| w.show_page(page));
            bring_to_front(existing);
            return Ok(());
        }
    }
    let config = ctx.load_config().map_err(|e| e.to_string())?;
    let hwnd = create_window()?;
    // SAFETY: no preconditions.
    let scale = unsafe { GetDpiForWindow(hwnd) } as f32 / BASE_DPI;
    let points = |pt: f32| (pt * BASE_DPI * scale / 72.0).round() as i32;
    let fonts = [gdi::font(points(FONT_POINTS), FW_NORMAL), gdi::font(points(TITLE_POINTS), FW_SEMIBOLD)];
    let icons = set_icons(hwnd);

    let mut b = Builder::new(hwnd, scale, &fonts[0], &fonts[1]);
    let titles: Vec<&str> = SettingsPage::ALL.iter().map(|p| p.title()).collect();
    let nav = b.navigation(&titles, ID_NAV);
    let status = b.text("", (LEFT, CLIENT_H - 40, 380, 20));
    b.default_button("Save", (CLIENT_W - 224, CLIENT_H - 46, 96, 30), ID_SAVE);
    b.button("Close", CLIENT_W - 120, CLIENT_H - 46, 96, ID_CLOSE);
    b.take_controls().into_iter().for_each(|c| set_visible(c, true));

    let mut slots = Vec::with_capacity(SettingsPage::ALL.len());
    for (i, page) in SettingsPage::ALL.into_iter().enumerate() {
        b.begin_page(PAGE_ID_BASE + PAGE_ID_STRIDE * u16::try_from(i).unwrap_or(0));
        let page = pages::build(page, &mut b);
        slots.push(PageSlot { page, controls: b.take_controls() });
    }
    drop(b);

    let mut window = SettingsWindow {
        hwnd,
        owner,
        ctx: ctx.clone(),
        nav,
        status,
        pages: slots,
        current: None,
        working: config,
        _fonts: fonts,
        _icons: icons,
    };
    for page in SettingsPage::ALL {
        window.on_page(page, |p, config, cx| p.load(config, cx));
    }
    window.show_page(page);
    WINDOW.with(|w| *w.borrow_mut() = Some(window));
    bring_to_front(hwnd);
    Ok(())
}

fn bring_to_front(hwnd: HWND) {
    // SAFETY: valid window handle.
    unsafe {
        let _ = ShowWindow(hwnd, SW_SHOWNORMAL);
        let _ = SetForegroundWindow(hwnd);
    }
}

/// Registers the classes and creates the (hidden) top-level window, sized
/// for the monitor's DPI.
fn create_window() -> Result<HWND> {
    let class = w!("VoiceInkSettings");
    let style = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX;
    // SAFETY: static class names with valid window procedures; the window is
    // created hidden and resized before it is shown.
    unsafe {
        let instance = GetModuleHandleW(None).context("module handle")?;
        RegisterClassW(&WNDCLASSW {
            lpfnWndProc: Some(wnd_proc),
            hInstance: instance.into(),
            lpszClassName: class,
            hCursor: LoadCursorW(None, IDC_ARROW).unwrap_or_default(),
            hbrBackground: GetSysColorBrush(COLOR_WINDOW),
            ..Default::default()
        });
        stats_panel::register(instance.into());
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
        .context("create the settings window")?;
        let scale = GetDpiForWindow(hwnd) as f32 / BASE_DPI;
        let mut rect =
            RECT { left: 0, top: 0, right: (CLIENT_W as f32 * scale) as i32, bottom: (CLIENT_H as f32 * scale) as i32 };
        let _ = AdjustWindowRectEx(&raw mut rect, style, false, WS_EX_CONTROLPARENT);
        let (width, height) = (rect.right - rect.left, rect.bottom - rect.top);
        let _ = SetWindowPos(hwnd, None, 0, 0, width, height, SWP_NOMOVE | SWP_NOZORDER);
        Ok(hwnd)
    }
}

/// Sets the title-bar and taskbar icons; the returned icons must outlive the window.
fn set_icons(hwnd: HWND) -> Vec<OwnedIcon> {
    [(32, ICON_BIG), (16, ICON_SMALL)]
        .into_iter()
        .filter_map(|(size, kind)| {
            let icon = create_icon(size, IconState::Idle)?;
            // SAFETY: WM_SETICON takes the icon handle in lParam; the icon is
            // kept alive in the window state.
            unsafe {
                SendMessageW(hwnd, WM_SETICON, Some(WPARAM(kind as usize)), Some(LPARAM(icon.handle().0 as isize)));
            }
            Some(icon)
        })
        .collect()
}
