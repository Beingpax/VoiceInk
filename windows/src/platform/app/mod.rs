//! The tray application (the Windows counterpart of `VoiceInkEngine` +
//! `RecorderUIManager`).
//!
//! * [`mod@self`] — the hidden main window, its message loop and the
//!   single-instance check; it routes window messages to the [`App`].
//! * [`controller`] — the recording state machine.
//! * [`menu`] — the tray menu and its actions.
//! * [`delivery`] — pasting / custom commands on worker threads.
//! * [`events`] — worker → UI thread messages.
//! * [`config_file`] — the settings file and its reloading.
//!
//! Everything UI-related runs on the main thread; transcription, enhancement
//! and pasting run on worker threads that report back through [`events`].

mod config_file;
mod controller;
mod delivery;
mod events;
mod menu;

use super::com::ComGuard;
use super::error::{Context, Result};
use super::hotkey::{self, WM_HOTKEY_EVENT};
use super::overlay::{Overlay, WM_OVERLAY_CLICKED};
use super::settings::{self, WM_SETTINGS_SAVED};
use super::tray::{NIN_KEYSELECT, NIN_SELECT, NoticeKind, WM_TRAY};
use crate::context::AppContext;
use crate::input::HotkeyEvent;
use crate::settings_page::SettingsPage;
use config_file::ConfigFile;
use controller::{App, Followup, MUTE_TIMER};
use events::{Notice, WM_UI_EVENT};
use std::cell::RefCell;
use std::sync::atomic::{AtomicU32, Ordering};
use windows::Win32::Foundation::{
    CloseHandle, ERROR_ALREADY_EXISTS, GetLastError, HANDLE, HWND, LPARAM, LRESULT, WPARAM,
};
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::System::Threading::CreateMutexW;
use windows::Win32::UI::Accessibility::{HWINEVENTHOOK, SetWinEventHook, UnhookWinEvent};
use windows::Win32::UI::HiDpi::{DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2, SetProcessDpiAwarenessContext};
use windows::Win32::UI::WindowsAndMessaging::{
    ASFW_ANY, AllowSetForegroundWindow, CreateWindowExW, DefWindowProcW, DestroyWindow, DispatchMessageW,
    EVENT_SYSTEM_FOREGROUND, FindWindowW, GetMessageW, IsDialogMessageW, KillTimer, MSG, PostMessageW, PostQuitMessage,
    RegisterClassW, RegisterWindowMessageW, SetTimer, TranslateMessage, WINDOW_EX_STYLE, WINEVENT_OUTOFCONTEXT, WM_APP,
    WM_CLOSE, WM_CONTEXTMENU, WM_DESTROY, WM_TIMER, WNDCLASSW, WS_OVERLAPPED,
};
use windows::core::{PCWSTR, w};

/// Sent by `voiceink dashboard` / `voiceink settings` to the running
/// instance; `wParam` is a [`SettingsPage::index`].
const WM_OPEN_SETTINGS: u32 = WM_APP + 9;
const MAIN_CLASS: PCWSTR = w!("VoiceInkMainWindow");
const INSTANCE_MUTEX: PCWSTR = w!("Local\\VoiceInkWindowsSingleInstance");
/// Retries delivering worker events while the app is busy in a nested loop.
const EVENT_RETRY_TIMER: usize = 11;
const EVENT_RETRY_MS: u32 = 50;

thread_local! {
    static APP: RefCell<Option<App>> = const { RefCell::new(None) };
}

/// The `TaskbarCreated` broadcast (Explorer restarted; re-add the tray icon).
static TASKBAR_CREATED: AtomicU32 = AtomicU32::new(0);

/// Runs `f` on the app. `None` when it is gone or already borrowed further up
/// the stack (re-entered from a nested message loop).
fn with_app<R>(f: impl FnOnce(&mut App) -> R) -> Option<R> {
    APP.with(|app| app.try_borrow_mut().ok()?.as_mut().map(f))
}

fn notify(notice: &Notice) {
    with_app(|app| app.notify(notice));
}

fn open_settings(hwnd: HWND, page: SettingsPage) {
    let Some(ctx) = with_app(|app| app.context().clone()) else { return };
    if let Err(e) = settings::open(hwnd, &ctx, page) {
        notify(&Notice::new("Could not open settings", e.to_string(), NoticeKind::Error));
    }
}

fn run_followup(hwnd: HWND, followup: Option<Followup>) {
    match followup {
        Some(Followup::OpenSettings(page)) => open_settings(hwnd, page),
        // SAFETY: our own window; WM_DESTROY takes the app down.
        Some(Followup::Quit) => drop(unsafe { DestroyWindow(hwnd) }),
        None => {}
    }
}

fn show_tray_menu(hwnd: HWND) {
    // Build inside a short borrow; tracking the menu runs a nested loop.
    let Some((menu, items)) = with_app(|app| app.menu()) else { return };
    let chosen = menu.track(hwnd);
    drop(menu);
    if let Some(action) = items.take(chosen) {
        run_followup(hwnd, with_app(|app| app.on_menu(action)).flatten());
    }
}

unsafe extern "system" fn foreground_changed(
    _hook: HWINEVENTHOOK,
    _event: u32,
    hwnd: HWND,
    _object: i32,
    _child: i32,
    _thread: u32,
    _time: u32,
) {
    with_app(|app| app.foreground_changed(hwnd));
}

unsafe extern "system" fn wnd_proc(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    match msg {
        WM_HOTKEY_EVENT => {
            if let Some(event) = HotkeyEvent::from_wparam(wparam.0) {
                with_app(|app| app.on_hotkey(event));
            }
        }
        WM_UI_EVENT => {
            if with_app(App::drain_events).is_none() {
                // SAFETY: our own window; the timer is killed when it fires.
                unsafe { SetTimer(Some(hwnd), EVENT_RETRY_TIMER, EVENT_RETRY_MS, None) };
            }
        }
        WM_TIMER if wparam.0 == EVENT_RETRY_TIMER => {
            if with_app(App::drain_events).is_some() {
                // SAFETY: our own window and timer.
                let _ = unsafe { KillTimer(Some(hwnd), EVENT_RETRY_TIMER) };
            }
        }
        WM_TIMER if wparam.0 == MUTE_TIMER => {
            with_app(App::mute_timer_elapsed);
        }
        WM_OPEN_SETTINGS => open_settings(hwnd, SettingsPage::from_index(wparam.0).unwrap_or(SettingsPage::Dashboard)),
        WM_SETTINGS_SAVED => {
            with_app(|app| app.reload_config(true, false));
        }
        WM_OVERLAY_CLICKED => {
            with_app(App::overlay_clicked);
        }
        WM_TRAY => {
            // NOTIFYICON_VERSION_4: the event is LOWORD(lParam).
            match (lparam.0 & 0xFFFF) as u32 {
                NIN_SELECT | NIN_KEYSELECT => open_settings(hwnd, SettingsPage::Dashboard),
                WM_CONTEXTMENU => show_tray_menu(hwnd),
                _ => {}
            }
        }
        WM_CLOSE => {
            // SAFETY: our own window.
            let _ = unsafe { DestroyWindow(hwnd) };
        }
        WM_DESTROY => {
            hotkey::uninstall();
            if let Some(mut app) = APP.with(|app| app.try_borrow_mut().ok().and_then(|mut a| a.take())) {
                app.shutdown();
            }
            // SAFETY: ends this thread's message loop.
            unsafe { PostQuitMessage(0) };
        }
        m if m != 0 && m == TASKBAR_CREATED.load(Ordering::Relaxed) => {
            with_app(App::restore_tray_icon);
        }
        // SAFETY: default handling for everything else.
        _ => return unsafe { DefWindowProcW(hwnd, msg, wparam, lparam) },
    }
    LRESULT(0)
}

/// Asks an already running instance to show `page`. False if none runs.
pub fn open_settings_in_running_instance(page: SettingsPage) -> bool {
    // SAFETY: looks up a window by our private class name and posts to it.
    unsafe {
        match FindWindowW(MAIN_CLASS, None) {
            Ok(hwnd) if !hwnd.is_invalid() => {
                // Let the running instance take the foreground.
                let _ = AllowSetForegroundWindow(ASFW_ANY);
                PostMessageW(Some(hwnd), WM_OPEN_SETTINGS, WPARAM(page.index()), LPARAM(0)).is_ok()
            }
            _ => false,
        }
    }
}

/// Holds the per-session mutex that keeps a second instance from starting.
struct SingleInstance(HANDLE);

impl SingleInstance {
    /// `None` when another instance already owns the mutex.
    fn acquire() -> Result<Option<Self>> {
        // SAFETY: a static name; the handle is closed in Drop.
        let handle = unsafe { CreateMutexW(None, true, INSTANCE_MUTEX) }.context("single-instance mutex")?;
        // SAFETY: reads the error of the CreateMutexW call above.
        if unsafe { GetLastError() } == ERROR_ALREADY_EXISTS {
            // SAFETY: we own this handle (to an existing mutex).
            let _ = unsafe { CloseHandle(handle) };
            return Ok(None);
        }
        Ok(Some(Self(handle)))
    }
}

impl Drop for SingleInstance {
    fn drop(&mut self) {
        // SAFETY: closes the handle from `acquire` exactly once.
        let _ = unsafe { CloseHandle(self.0) };
    }
}

/// Watches which window has the focus (see [`App::foreground_changed`]).
struct ForegroundHook(HWINEVENTHOOK);

impl ForegroundHook {
    fn install() -> Self {
        // SAFETY: an out-of-context hook with a static callback; removed in Drop.
        Self(unsafe {
            SetWinEventHook(
                EVENT_SYSTEM_FOREGROUND,
                EVENT_SYSTEM_FOREGROUND,
                None,
                Some(foreground_changed),
                0,
                0,
                WINEVENT_OUTOFCONTEXT,
            )
        })
    }
}

impl Drop for ForegroundHook {
    fn drop(&mut self) {
        // SAFETY: removes the hook installed in `install`.
        let _ = unsafe { UnhookWinEvent(self.0) };
    }
}

/// A hidden top-level window (not message-only) so it receives the
/// `TaskbarCreated` broadcast and can own the tray icon and menus.
fn create_main_window() -> Result<HWND> {
    // SAFETY: a static class name with a valid window procedure.
    unsafe {
        let instance = GetModuleHandleW(None).context("module handle")?;
        RegisterClassW(&WNDCLASSW {
            lpfnWndProc: Some(wnd_proc),
            hInstance: instance.into(),
            lpszClassName: MAIN_CLASS,
            ..Default::default()
        });
        TASKBAR_CREATED.store(RegisterWindowMessageW(w!("TaskbarCreated")), Ordering::Relaxed);
        CreateWindowExW(
            WINDOW_EX_STYLE::default(),
            MAIN_CLASS,
            w!("VoiceInk"),
            WS_OVERLAPPED,
            0,
            0,
            0,
            0,
            None,
            None,
            Some(instance.into()),
            None,
        )
        .context("create the main window")
    }
}

fn message_loop() {
    let mut msg = MSG::default();
    // SAFETY: the standard message loop on the thread that owns the windows.
    unsafe {
        while GetMessageW(&raw mut msg, None, 0, 0).as_bool() {
            // Tab / Enter / Esc navigation inside the settings window.
            if let Some(dialog) = settings::dialog_hwnd()
                && IsDialogMessageW(dialog, &raw const msg).as_bool()
            {
                continue;
            }
            let _ = TranslateMessage(&raw const msg);
            DispatchMessageW(&raw const msg);
        }
    }
}

/// Runs the tray app until the user quits; `open_page` shows the dashboard
/// or settings right away.
///
/// # Errors
/// Fails when the settings file is invalid or a window cannot be created.
pub fn run(ctx: &AppContext, open_page: Option<SettingsPage>) -> Result<()> {
    let Some(_instance) = SingleInstance::acquire()? else {
        if open_settings_in_running_instance(open_page.unwrap_or(SettingsPage::Dashboard)) {
            return Ok(());
        }
        return Err("VoiceInk is already running — look for its icon in the notification area.".into());
    };
    // SAFETY: called before any window is created.
    let _ = unsafe { SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2) };
    let _com = ComGuard::apartment_threaded()?;

    let first_run = !ctx.paths.config().exists();
    let config = ConfigFile::open(ctx.paths.config()).map_err(|e| e.to_string())?;
    let hwnd = create_main_window()?;
    let overlay = Overlay::create(hwnd, config.get().overlay)?;
    let app = App::new(hwnd, ctx.clone(), config, overlay, events::channel(hwnd));
    APP.with(|slot| *slot.borrow_mut() = Some(app));
    let _foreground_hook = ForegroundHook::install();

    with_app(|app| {
        app.apply_config();
        app.greet(first_run);
    });
    log::info!("ready; settings at {}", ctx.paths.config().display());
    if let Some(page) = open_page {
        open_settings(hwnd, page);
    }
    message_loop();
    Ok(())
}
