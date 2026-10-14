//! The tray application: window, message loop and recording state machine
//! (the Windows counterpart of `VoiceInkEngine` + `RecorderUIManager`).
//!
//! Everything UI-related runs on the main thread. Transcription, enhancement
//! and pasting run on worker threads that report back with `PostMessageW`.

use super::capture::Recorder;
use super::hotkey::{self, HotkeyEvent, WM_HOTKEY_EVENT};
use super::icon::IconState;
use super::overlay::{Overlay, View, WM_OVERLAY_CLICKED};
use super::settings::{self, WM_SETTINGS_SAVED};
use super::sound::{self, Cue};
use super::tray::{Menu, NoticeKind, Tray, WM_TRAY};
use super::{autostart, clipboard, foreground, paste, prompt, volume, wide};
use crate::config::{
    self, Config, EnhancementProvider, HotkeyMode, OutputMode, PasteMethod, TranscriptionProvider,
    LANGUAGES,
};
use crate::history::{self, Status};
use crate::modes::{self, ForegroundInfo};
use crate::pipeline::{self, Delivery, PipelineInput, PipelineOutput, Stage};
use crate::{credentials, APP_VERSION};
use std::cell::RefCell;
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime};
use windows::core::{w, PCWSTR};
use windows::Win32::Foundation::{
    GetLastError, ERROR_ALREADY_EXISTS, HWND, LPARAM, LRESULT, WPARAM,
};
use windows::Win32::System::Com::{CoInitializeEx, COINIT_APARTMENTTHREADED};
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::System::Threading::{CreateMutexW, GetCurrentProcessId};
use windows::Win32::UI::Accessibility::{SetWinEventHook, HWINEVENTHOOK};
use windows::Win32::UI::HiDpi::{
    SetProcessDpiAwarenessContext, DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2,
};
use windows::Win32::UI::Shell::ShellExecuteW;
use windows::Win32::UI::WindowsAndMessaging::{
    AllowSetForegroundWindow, CreateWindowExW, DefWindowProcW, DestroyWindow, DispatchMessageW,
    FindWindowW, GetClassNameW, GetMessageW, GetWindowThreadProcessId, IsDialogMessageW, KillTimer,
    PostMessageW, PostQuitMessage, RegisterClassW, RegisterWindowMessageW, SetTimer,
    TranslateMessage, ASFW_ANY, EVENT_SYSTEM_FOREGROUND, MSG, SW_SHOWNORMAL, WINEVENT_OUTOFCONTEXT,
    WM_APP, WM_CLOSE, WM_CONTEXTMENU, WM_DESTROY, WM_TIMER, WNDCLASSW, WS_OVERLAPPED,
};

const WM_PIPELINE_STAGE: u32 = WM_APP + 2;
const WM_PIPELINE_DONE: u32 = WM_APP + 3;
const WM_NOTICE: u32 = WM_APP + 7;
/// Sent by `voiceink dashboard` / `voiceink settings` to the running instance; `wParam` = page.
const WM_OPEN_SETTINGS: u32 = WM_APP + 9;
const MAIN_CLASS: PCWSTR = w!("VoiceInkMainWindow");
const MUTE_TIMER: usize = 10;
const MUTE_DELAY_MS: u32 = 250;

// Menu command ids.
const CMD_TOGGLE: usize = 1;
const CMD_PASTE_LAST: usize = 2;
const CMD_ENHANCE: usize = 3;
const CMD_TRANSCRIPTION_BASE: usize = 100;
const CMD_PROMPT_BASE: usize = 200;
const CMD_ENHANCER_BASE: usize = 300;
const CMD_LANGUAGE_BASE: usize = 400;
const CMD_HOTKEY_MODE_BASE: usize = 500;
const CMD_OUTPUT_BASE: usize = 520;
const CMD_KEY_BASE: usize = 540;
const CMD_AUTOSTART: usize = 600;
const CMD_OPEN_SETTINGS: usize = 601;
const CMD_RELOAD: usize = 602;
const CMD_OPEN_FOLDER: usize = 603;
const CMD_OPEN_HISTORY: usize = 604;
const CMD_ABOUT: usize = 605;
const CMD_QUIT: usize = 606;
const CMD_FORMATTING: usize = 607;
const CMD_RESTORE_CLIPBOARD: usize = 608;
const CMD_SOUNDS: usize = 609;
const CMD_MUTE: usize = 610;
const CMD_DASHBOARD: usize = 611;
const CMD_SETTINGS: usize = 612;

/// Work that must run after the app borrow is released (it pumps messages).
enum Followup {
    AskKey(&'static str),
    OpenSettings(usize),
}

/// Results handed from worker threads to the UI thread.
static RESULTS: Mutex<Vec<(u64, PipelineOutput)>> = Mutex::new(Vec::new());
/// Notifications raised on worker threads.
static NOTICES: Mutex<Vec<(String, String, NoticeKind)>> = Mutex::new(Vec::new());

/// `HWND` is not `Send`; worker threads carry the raw value.
#[derive(Clone, Copy)]
struct SendHwnd(isize);

impl SendHwnd {
    fn new(h: HWND) -> Self {
        SendHwnd(h.0 as isize)
    }
    fn get(self) -> HWND {
        HWND(self.0 as *mut _)
    }
}

fn post_notice(hwnd: SendHwnd, title: &str, message: &str, kind: NoticeKind) {
    NOTICES
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .push((title.into(), message.into(), kind));
    unsafe {
        let _ = PostMessageW(Some(hwnd.get()), WM_NOTICE, WPARAM(0), LPARAM(0));
    }
}

struct RecordingSession {
    recorder: Recorder,
    target: HWND,
    foreground: ForegroundInfo,
    clipboard_text: Option<String>,
    selected_text: Arc<Mutex<Option<String>>>,
    /// Whether the current key press started this recording (push-to-talk logic).
    started_by_press: bool,
    mute: Option<volume::MuteGuard>,
}

struct Job {
    id: u64,
    cancel: Arc<AtomicBool>,
    target: HWND,
}

enum State {
    Idle,
    Recording(Box<RecordingSession>),
    Processing(Job),
}

struct App {
    hwnd: HWND,
    config: Config,
    config_mtime: Option<SystemTime>,
    tray: Tray,
    overlay: Overlay,
    state: State,
    next_job: u64,
    /// Last focused window that isn't VoiceInk or the taskbar (target for menu-started recordings).
    last_external: HWND,
    canceled_jobs: HashMap<u64, ()>,
}

thread_local! {
    static APP: RefCell<Option<App>> = const { RefCell::new(None) };
    static TASKBAR_CREATED: std::cell::Cell<u32> = const { std::cell::Cell::new(0) };
}

fn with_app<R>(f: impl FnOnce(&mut App) -> R) -> Option<R> {
    APP.with(|a| {
        // Re-entrancy (nested message loops in menus/dialogs) must not double-borrow.
        let mut guard = a.try_borrow_mut().ok()?;
        guard.as_mut().map(f)
    })
}

fn config_mtime() -> Option<SystemTime> {
    std::fs::metadata(config::config_path())
        .and_then(|m| m.modified())
        .ok()
}

fn open_path(path: &std::path::Path) {
    let p = wide(&path.to_string_lossy());
    unsafe {
        ShellExecuteW(
            None,
            w!("open"),
            PCWSTR(p.as_ptr()),
            None,
            None,
            SW_SHOWNORMAL,
        );
    }
}

impl App {
    fn tip(&self) -> String {
        let status = match self.state {
            State::Idle => "Ready",
            State::Recording(_) => "Recording…",
            State::Processing(_) => "Processing…",
        };
        format!("VoiceInk — {status}\n{}", self.config.hotkeys.record)
    }

    fn refresh_tray(&self) {
        let icon = match self.state {
            State::Idle => IconState::Idle,
            State::Recording(_) => IconState::Recording,
            State::Processing(_) => IconState::Busy,
        };
        self.tray.set_state(icon, &self.tip());
        hotkey::set_active(!matches!(self.state, State::Idle));
    }

    fn notify(&self, title: &str, message: &str, kind: NoticeKind) {
        log::info!("notice: {title}: {message}");
        self.tray.notify(title, message, kind);
    }

    fn save_config(&mut self) {
        if let Err(e) = self.config.save(&config::config_path()) {
            self.notify("Could not save settings", &e, NoticeKind::Error);
        }
        self.config_mtime = config_mtime();
    }

    fn apply_config(&mut self) {
        match hotkey::install(self.hwnd, &self.config.hotkeys) {
            Ok(problems) if !problems.is_empty() => {
                self.notify("Hotkey problem", &problems.join("\n"), NoticeKind::Warning)
            }
            Ok(_) => {}
            Err(e) => self.notify("Hotkeys unavailable", &e, NoticeKind::Error),
        }
        self.overlay.set_position(self.config.overlay);
        self.refresh_tray();
    }

    /// Picks up hand edits to `config.json`.
    fn reload_if_changed(&mut self, force: bool, announce: bool) {
        let mtime = config_mtime();
        if !force && mtime == self.config_mtime {
            return;
        }
        match Config::load(&config::config_path()) {
            Ok(cfg) => {
                self.config = cfg;
                self.config_mtime = mtime;
                self.apply_config();
                if announce {
                    self.notify("Settings reloaded", "", NoticeKind::Info);
                }
            }
            Err(e) => self.notify("Settings file has an error", &e, NoticeKind::Error),
        }
    }

    // -- recording ----------------------------------------------------------

    fn start_recording(&mut self, by_press: bool) {
        self.reload_if_changed(false, false);

        let (mut target, mut fg) = foreground::current();
        if is_own_or_shell(target) && !self.last_external.is_invalid() {
            target = self.last_external;
            fg = ForegroundInfo {
                process_name: foreground::process_name(target),
                window_title: foreground::window_title(target),
            };
            foreground::restore_focus(target);
        }

        let mode = modes::match_mode(&self.config.modes, &fg);
        let resolved = modes::resolve(&self.config, mode);
        let clipboard_text = resolved
            .use_clipboard_context
            .then(clipboard::get_text)
            .flatten();

        if self.config.audio.play_sounds {
            sound::play(Cue::Start, self.config.audio.start_sound.as_deref());
        }

        let recorder = match Recorder::start(self.config.audio.input_device.clone()) {
            Ok(r) => r,
            Err(e) => {
                log::error!("recording failed to start: {e}");
                self.notify("Could not start recording", &e, NoticeKind::Error);
                return;
            }
        };

        let selected_text = Arc::new(Mutex::new(None));
        if resolved.use_selected_text_context {
            let slot = selected_text.clone();
            std::thread::spawn(move || {
                let text = paste::copy_selection();
                *slot.lock().unwrap_or_else(|e| e.into_inner()) = text;
            });
        }

        self.overlay.show(View::Recording {
            started: Instant::now(),
            level: recorder.level_handle(),
            mode: resolved.mode_name.clone(),
        });
        if self.config.audio.mute_system_audio {
            unsafe {
                SetTimer(Some(self.hwnd), MUTE_TIMER, MUTE_DELAY_MS, None);
            }
        }

        self.state = State::Recording(Box::new(RecordingSession {
            recorder,
            target,
            foreground: fg,
            clipboard_text,
            selected_text,
            started_by_press: by_press,
            mute: None,
        }));
        self.refresh_tray();
    }

    fn cancel_recording(&mut self, play_sound: bool) {
        if let State::Recording(session) = std::mem::replace(&mut self.state, State::Idle) {
            let session = *session;
            drop(session.mute);
            session.recorder.cancel();
            if play_sound && self.config.audio.play_sounds {
                sound::play(Cue::Cancel, None);
            }
        }
        self.overlay.hide();
        self.refresh_tray();
    }

    fn stop_recording(&mut self) {
        let State::Recording(session) = std::mem::replace(&mut self.state, State::Idle) else {
            return;
        };
        let session = *session;
        unsafe {
            let _ = KillTimer(Some(self.hwnd), MUTE_TIMER);
        }
        drop(session.mute);
        let elapsed = session.recorder.elapsed();
        let samples = match session.recorder.finish() {
            Ok(s) => s,
            Err(e) => {
                self.overlay.hide();
                self.notify("Recording failed", &e, NoticeKind::Error);
                self.refresh_tray();
                return;
            }
        };
        if self.config.audio.play_sounds {
            sound::play(Cue::Stop, self.config.audio.stop_sound.as_deref());
        }
        if elapsed < Duration::from_millis(self.config.audio.min_recording_ms) || samples.is_empty()
        {
            self.overlay.hide();
            self.refresh_tray();
            return;
        }

        let selected_text = session
            .selected_text
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .take();
        let input = PipelineInput {
            samples,
            foreground: session.foreground,
            clipboard_text: session.clipboard_text,
            selected_text,
        };
        self.start_job(input, session.target);
    }

    fn start_job(&mut self, input: PipelineInput, target: HWND) {
        self.next_job += 1;
        let id = self.next_job;
        let cancel = Arc::new(AtomicBool::new(false));
        self.state = State::Processing(Job {
            id,
            cancel: cancel.clone(),
            target,
        });
        self.overlay.show(View::Transcribing);
        self.refresh_tray();

        let config = self.config.clone();
        let hwnd = SendHwnd::new(self.hwnd);
        std::thread::Builder::new()
            .name(format!("voiceink-job-{id}"))
            .spawn(move || {
                let on_stage = |stage: Stage| unsafe {
                    let s = match stage {
                        Stage::Transcribing => 0,
                        Stage::Enhancing => 1,
                    };
                    let _ = PostMessageW(
                        Some(hwnd.get()),
                        WM_PIPELINE_STAGE,
                        WPARAM(id as usize),
                        LPARAM(s),
                    );
                };
                let output = pipeline::run(&config, &input, &cancel, &on_stage);
                RESULTS
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .push((id, output));
                unsafe {
                    let _ = PostMessageW(
                        Some(hwnd.get()),
                        WM_PIPELINE_DONE,
                        WPARAM(id as usize),
                        LPARAM(0),
                    );
                }
            })
            .expect("spawn pipeline thread");
    }

    fn cancel_job(&mut self) {
        if let State::Processing(job) = std::mem::replace(&mut self.state, State::Idle) {
            job.cancel.store(true, Ordering::SeqCst);
            self.canceled_jobs.insert(job.id, ());
            if self.config.audio.play_sounds {
                sound::play(Cue::Cancel, None);
            }
        }
        self.overlay.hide();
        self.refresh_tray();
    }

    fn on_stage(&mut self, id: u64, stage: isize) {
        if matches!(&self.state, State::Processing(job) if job.id == id) {
            self.overlay.show(if stage == 1 {
                View::Enhancing
            } else {
                View::Transcribing
            });
        }
    }

    fn on_done(&mut self, id: u64) {
        let output = {
            let mut results = RESULTS.lock().unwrap_or_else(|e| e.into_inner());
            let pos = results.iter().position(|(i, _)| *i == id);
            pos.map(|p| results.remove(p).1)
        };
        let Some(mut output) = output else { return };

        let current = matches!(&self.state, State::Processing(job) if job.id == id);
        if self.canceled_jobs.remove(&id).is_some() || !current {
            output.entry.status = Status::Canceled;
            output.delivery = None;
        }
        self.save_history(&output);
        settings::refresh();

        if current {
            let State::Processing(job) = std::mem::replace(&mut self.state, State::Idle) else {
                unreachable!()
            };
            if let Some(err) = &output.error {
                self.overlay.show(View::Message {
                    text: "Transcription failed".into(),
                    until: Instant::now() + Duration::from_secs(3),
                });
                self.notify("Transcription failed", err, NoticeKind::Error);
            } else {
                self.overlay.hide();
            }
            if let Some(w) = &output.warning {
                self.notify("VoiceInk", w, NoticeKind::Warning);
            }
            if let Some(delivery) = output.delivery {
                self.deliver(delivery, job.target);
            }
            self.refresh_tray();
        }
    }

    fn save_history(&self, output: &PipelineOutput) {
        if !self.config.history.enabled {
            return;
        }
        let path = history::history_path();
        if let Err(e) = history::append(&path, &output.entry) {
            log::warn!("history write failed: {e}");
        }
        let _ = history::trim(&path, self.config.history.max_entries);
    }

    fn deliver(&self, delivery: Delivery, target: HWND) {
        let output_settings = self.config.output.clone();
        let hwnd = SendHwnd::new(self.hwnd);
        let target = SendHwnd::new(target);
        std::thread::spawn(move || match delivery.output {
            OutputMode::Paste => {
                foreground::restore_focus(target.get());
                if let Err(e) =
                    paste::paste_text(&delivery.text, &output_settings, delivery.send_key)
                {
                    post_notice(hwnd, "Paste failed", &e, NoticeKind::Warning);
                }
            }
            OutputMode::CustomCommand => {
                let Some(command) = delivery.custom_command else {
                    post_notice(
                        hwnd,
                        "Custom command",
                        "No command configured for this mode",
                        NoticeKind::Warning,
                    );
                    return;
                };
                if let Err(e) = run_custom_command(&command, &delivery.text) {
                    post_notice(hwnd, "Custom command failed", &e, NoticeKind::Warning);
                } else if delivery.send_key != crate::config::SendKey::None {
                    std::thread::sleep(Duration::from_millis(150));
                    paste::press_send_key(delivery.send_key);
                }
            }
        });
    }

    fn paste_last(&self) {
        match history::last_text(&history::history_path()) {
            Some(text) => self.deliver(
                Delivery {
                    text,
                    output: OutputMode::Paste,
                    custom_command: None,
                    send_key: crate::config::SendKey::None,
                },
                HWND::default(),
            ),
            None => self.notify(
                "Nothing to paste",
                "There is no transcription yet.",
                NoticeKind::Info,
            ),
        }
    }

    // -- hotkeys ------------------------------------------------------------

    fn on_hotkey(&mut self, event: HotkeyEvent) {
        let threshold = Duration::from_millis(self.config.hotkeys.hybrid_threshold_ms);
        match event {
            HotkeyEvent::RecordDown => match self.state {
                State::Idle => self.start_recording(true),
                State::Recording(_) => self.stop_recording(),
                State::Processing(_) => {}
            },
            HotkeyEvent::RecordUp => {
                let mode = self.config.hotkeys.mode;
                let stop = match &mut self.state {
                    State::Recording(s) if s.started_by_press => match mode {
                        HotkeyMode::PushToTalk => true,
                        HotkeyMode::Hybrid if s.recorder.elapsed() >= threshold => true,
                        HotkeyMode::Hybrid | HotkeyMode::Toggle => {
                            // Short tap: keep recording until the next press.
                            s.started_by_press = false;
                            false
                        }
                    },
                    _ => false,
                };
                if stop {
                    self.stop_recording();
                }
            }
            HotkeyEvent::RecordAbort => {
                let abort = matches!(&self.state,
                    State::Recording(s) if s.started_by_press && s.recorder.elapsed() < threshold);
                if abort {
                    self.cancel_recording(false);
                }
            }
            HotkeyEvent::Cancel => match self.state {
                State::Recording(_) => self.cancel_recording(true),
                State::Processing(_) => self.cancel_job(),
                State::Idle => {}
            },
            HotkeyEvent::PasteLast => {
                if matches!(self.state, State::Idle) {
                    self.paste_last();
                }
            }
        }
    }

    // -- menu ---------------------------------------------------------------

    fn build_menu(&self) -> Menu {
        let cfg = &self.config;
        let menu = Menu::new();
        menu.disabled(&format!("VoiceInk {APP_VERSION}"));
        menu.disabled(&format!("Shortcut: {}", hotkey::describe(&cfg.hotkeys)));
        menu.separator();
        menu.item(CMD_DASHBOARD, "Dashboard…");
        menu.item(CMD_SETTINGS, "Settings…");
        menu.separator();
        let toggle = match self.state {
            State::Idle => "Start recording",
            State::Recording(_) => "Stop recording",
            State::Processing(_) => "Cancel processing",
        };
        menu.item(CMD_TOGGLE, toggle);
        menu.item(CMD_PASTE_LAST, "Paste last transcription");
        menu.separator();

        let transcription = Menu::new();
        for (i, p) in TranscriptionProvider::ALL.iter().enumerate() {
            let suffix = if p.requires_api_key() && !credentials::has(p.key_name()) {
                "  (no key)"
            } else {
                ""
            };
            transcription.check(
                CMD_TRANSCRIPTION_BASE + i,
                &format!("{}{suffix}", p.display_name()),
                cfg.transcription.provider == *p,
            );
        }
        menu.submenu(
            &format!(
                "Transcription: {}",
                cfg.transcription.provider.display_name()
            ),
            transcription,
        );

        let languages = Menu::new();
        for (i, (code, name)) in LANGUAGES.iter().enumerate() {
            languages.check(
                CMD_LANGUAGE_BASE + i,
                name,
                cfg.transcription.language.eq_ignore_ascii_case(code),
            );
        }
        menu.submenu("Language", languages);

        let enhancement = Menu::new();
        enhancement.check(CMD_ENHANCE, "Enabled", cfg.enhancement.enabled);
        enhancement.separator();
        enhancement.disabled("Prompt");
        for (i, p) in cfg.prompts.iter().enumerate().take(90) {
            enhancement.check(
                CMD_PROMPT_BASE + i,
                &p.title,
                cfg.enhancement.prompt_id == p.id,
            );
        }
        enhancement.separator();
        enhancement.disabled("Provider");
        for (i, p) in EnhancementProvider::ALL.iter().enumerate() {
            let suffix = if p.requires_api_key() && !credentials::has(p.key_name()) {
                "  (no key)"
            } else {
                ""
            };
            enhancement.check(
                CMD_ENHANCER_BASE + i,
                &format!("{}{suffix}", p.display_name()),
                cfg.enhancement.provider == *p,
            );
        }
        menu.submenu(
            &format!(
                "AI Enhancement: {}",
                if cfg.enhancement.enabled { "On" } else { "Off" }
            ),
            enhancement,
        );

        let keys = Menu::new();
        for (i, name) in api_key_names().iter().enumerate() {
            let state = if credentials::has(name) { "✓" } else { "–" };
            keys.item(CMD_KEY_BASE + i, &format!("{state}  {name}…"));
        }
        menu.submenu("API keys", keys);

        let options = Menu::new();
        options.disabled("Shortcut behaviour");
        for (i, (mode, label)) in [
            (HotkeyMode::Hybrid, "Tap to toggle, hold to talk"),
            (HotkeyMode::Toggle, "Toggle"),
            (HotkeyMode::PushToTalk, "Push to talk"),
        ]
        .iter()
        .enumerate()
        {
            options.check(CMD_HOTKEY_MODE_BASE + i, label, cfg.hotkeys.mode == *mode);
        }
        options.separator();
        options.disabled("Insert text with");
        for (i, (method, label)) in [
            (PasteMethod::CtrlV, "Ctrl+V"),
            (PasteMethod::ShiftInsert, "Shift+Insert"),
            (PasteMethod::Type, "Simulated typing"),
        ]
        .iter()
        .enumerate()
        {
            options.check(CMD_OUTPUT_BASE + i, label, cfg.output.method == *method);
        }
        options.separator();
        options.check(
            CMD_RESTORE_CLIPBOARD,
            "Restore clipboard after paste",
            cfg.output.restore_clipboard,
        );
        options.check(
            CMD_FORMATTING,
            "Paragraph formatting",
            cfg.transcription.text_formatting,
        );
        options.check(CMD_SOUNDS, "Sound feedback", cfg.audio.play_sounds);
        options.check(
            CMD_MUTE,
            "Mute system audio while recording",
            cfg.audio.mute_system_audio,
        );
        menu.submenu("Options", options);

        menu.separator();
        menu.check(CMD_AUTOSTART, "Start with Windows", autostart::is_enabled());
        menu.item(CMD_OPEN_SETTINGS, "Open settings file");
        menu.item(CMD_RELOAD, "Reload settings");
        menu.item(CMD_OPEN_HISTORY, "Open history (CSV)");
        menu.item(CMD_OPEN_FOLDER, "Open data folder");
        menu.separator();
        menu.item(CMD_ABOUT, "About VoiceInk");
        menu.item(CMD_QUIT, "Quit");
        menu
    }

    /// Handles a menu command. Returns the API key name to ask for, if any; the
    /// dialog must run after the app borrow is released (it pumps messages).
    fn on_command(&mut self, cmd: usize) -> Option<Followup> {
        let mut ask = None;
        let in_range =
            |base: usize, len: usize| (base..base + len).contains(&cmd).then(|| cmd - base);

        if let Some(i) = in_range(CMD_TRANSCRIPTION_BASE, TranscriptionProvider::ALL.len()) {
            let p = TranscriptionProvider::ALL[i];
            if p != self.config.transcription.provider {
                self.config.transcription.provider = p;
                self.config.transcription.model = None;
            }
            self.save_config();
            if p.requires_api_key() && !credentials::has(p.key_name()) {
                ask = Some(Followup::AskKey(p.key_name()));
            }
        } else if let Some(i) = in_range(CMD_PROMPT_BASE, self.config.prompts.len().min(90)) {
            self.config.enhancement.prompt_id = self.config.prompts[i].id.clone();
            self.save_config();
        } else if let Some(i) = in_range(CMD_ENHANCER_BASE, EnhancementProvider::ALL.len()) {
            let p = EnhancementProvider::ALL[i];
            if p != self.config.enhancement.provider {
                self.config.enhancement.provider = p;
                self.config.enhancement.model = None;
            }
            self.save_config();
            if p.requires_api_key() && !credentials::has(p.key_name()) {
                ask = Some(Followup::AskKey(p.key_name()));
            }
        } else if let Some(i) = in_range(CMD_LANGUAGE_BASE, LANGUAGES.len()) {
            self.config.transcription.language = LANGUAGES[i].0.into();
            self.save_config();
        } else if let Some(i) = in_range(CMD_HOTKEY_MODE_BASE, 3) {
            self.config.hotkeys.mode = [
                HotkeyMode::Hybrid,
                HotkeyMode::Toggle,
                HotkeyMode::PushToTalk,
            ][i];
            self.save_config();
            self.apply_config();
        } else if let Some(i) = in_range(CMD_OUTPUT_BASE, 3) {
            self.config.output.method = [
                PasteMethod::CtrlV,
                PasteMethod::ShiftInsert,
                PasteMethod::Type,
            ][i];
            self.save_config();
        } else if let Some(i) = in_range(CMD_KEY_BASE, api_key_names().len()) {
            ask = Some(Followup::AskKey(api_key_names()[i]));
        } else {
            match cmd {
                CMD_TOGGLE => match self.state {
                    State::Idle => self.start_recording(false),
                    State::Recording(_) => self.stop_recording(),
                    State::Processing(_) => self.cancel_job(),
                },
                CMD_PASTE_LAST => self.paste_last(),
                CMD_ENHANCE => {
                    self.config.enhancement.enabled = !self.config.enhancement.enabled;
                    self.save_config();
                    let p = self.config.enhancement.provider;
                    if self.config.enhancement.enabled && p.requires_api_key() && !credentials::has(p.key_name()) {
                        ask = Some(Followup::AskKey(p.key_name()));
                    }
                }
                CMD_FORMATTING => {
                    self.config.transcription.text_formatting = !self.config.transcription.text_formatting;
                    self.save_config();
                }
                CMD_RESTORE_CLIPBOARD => {
                    self.config.output.restore_clipboard = !self.config.output.restore_clipboard;
                    self.save_config();
                }
                CMD_SOUNDS => {
                    self.config.audio.play_sounds = !self.config.audio.play_sounds;
                    self.save_config();
                }
                CMD_MUTE => {
                    self.config.audio.mute_system_audio = !self.config.audio.mute_system_audio;
                    self.save_config();
                }
                CMD_AUTOSTART => {
                    let enable = !autostart::is_enabled();
                    match autostart::set_enabled(enable) {
                        Ok(()) => {
                            self.config.start_with_windows = enable;
                            self.save_config();
                        }
                        Err(e) => self.notify("Could not change autostart", &e, NoticeKind::Error),
                    }
                }
                CMD_OPEN_SETTINGS => open_path(&config::config_path()),
                CMD_RELOAD => self.reload_if_changed(true, true),
                CMD_OPEN_FOLDER => open_path(&config::data_dir()),
                CMD_OPEN_HISTORY => {
                    let out = config::data_dir().join("history.csv");
                    let entries = history::load(&history::history_path());
                    match std::fs::File::create(&out).and_then(|mut f| history::export_csv(&entries, &mut f)) {
                        Ok(()) => open_path(&out),
                        Err(e) => self.notify("Could not export history", &e.to_string(), NoticeKind::Error),
                    }
                }
                CMD_ABOUT => self.notify(
                    &format!("VoiceInk for Windows {APP_VERSION}"),
                    "Voice to text in any app. Press your shortcut, speak, and the text is pasted where your cursor is.",
                    NoticeKind::Info,
                ),
                CMD_DASHBOARD => ask = Some(Followup::OpenSettings(0)),
                CMD_SETTINGS => ask = Some(Followup::OpenSettings(1)),
                CMD_QUIT => unsafe {
                    let _ = DestroyWindow(self.hwnd);
                },
                _ => {}
            }
        }
        self.refresh_tray();
        ask
    }

    fn store_key(&mut self, name: &str, key: &str) {
        match credentials::set(name, key) {
            Ok(()) if key.trim().is_empty() => {
                self.notify("API key removed", name, NoticeKind::Info)
            }
            Ok(()) => self.notify("API key saved", name, NoticeKind::Info),
            Err(e) => self.notify("Could not save API key", &e, NoticeKind::Error),
        }
        self.refresh_tray();
    }
}

fn open_settings(hwnd: HWND, page: usize) {
    if let Err(e) = settings::open(hwnd, page) {
        with_app(|app| app.notify("Could not open settings", &e, NoticeKind::Error));
    }
}

/// Asks for an API key (outside any app borrow) and stores it.
fn ask_and_store_key(hwnd: HWND, name: &str) {
    let message = format!(
        "Enter the API key for {name}. It is encrypted for your Windows account (DPAPI). Leave empty to remove it."
    );
    if let Some(key) = prompt::ask(hwnd, &format!("VoiceInk — {name} API key"), &message, true) {
        with_app(|app| app.store_key(name, &key));
    }
}

fn api_key_names() -> Vec<&'static str> {
    let mut names: Vec<&str> = TranscriptionProvider::ALL
        .iter()
        .map(|p| p.key_name())
        .chain(EnhancementProvider::ALL.iter().map(|p| p.key_name()))
        .filter(|n| !n.is_empty())
        .collect();
    names.sort_unstable();
    names.dedup();
    names
}

/// Runs a mode's custom command with the text on stdin and in `VOICEINK_TRANSCRIPT`.
fn run_custom_command(command: &str, text: &str) -> Result<(), String> {
    use std::io::Write;
    use std::os::windows::process::CommandExt;
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;

    let mut child = std::process::Command::new("cmd")
        .args(["/D", "/S", "/C", command])
        .env("VOICEINK_TRANSCRIPT", text)
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .creation_flags(CREATE_NO_WINDOW)
        .spawn()
        .map_err(|e| e.to_string())?;
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(text.as_bytes());
    }
    let deadline = Instant::now() + Duration::from_secs(10);
    loop {
        if let Some(status) = child.try_wait().map_err(|e| e.to_string())? {
            if status.success() {
                return Ok(());
            }
            let out = child.wait_with_output().map_err(|e| e.to_string())?;
            return Err(format!(
                "exit code {}: {}",
                status.code().unwrap_or(-1),
                String::from_utf8_lossy(&out.stderr).trim()
            ));
        }
        if Instant::now() > deadline {
            let _ = child.kill();
            return Err("timed out after 10 seconds".into());
        }
        std::thread::sleep(Duration::from_millis(50));
    }
}

fn is_own_or_shell(hwnd: HWND) -> bool {
    if hwnd.is_invalid() {
        return true;
    }
    unsafe {
        let mut pid = 0u32;
        GetWindowThreadProcessId(hwnd, Some(&mut pid));
        if pid == GetCurrentProcessId() {
            return true;
        }
        let mut buf = [0u16; 64];
        let n = GetClassNameW(hwnd, &mut buf);
        let class = String::from_utf16_lossy(&buf[..n.max(0) as usize]);
        matches!(
            class.as_str(),
            "Shell_TrayWnd"
                | "Shell_SecondaryTrayWnd"
                | "NotifyIconOverflowWindow"
                | "TopLevelWindowForOverflowXamlIsland"
        )
    }
}

unsafe extern "system" fn foreground_changed(
    _hook: HWINEVENTHOOK,
    _event: u32,
    hwnd: HWND,
    _id_object: i32,
    _id_child: i32,
    _thread: u32,
    _time: u32,
) {
    if !is_own_or_shell(hwnd) {
        with_app(|app| app.last_external = hwnd);
    }
}

unsafe extern "system" fn wnd_proc(
    hwnd: HWND,
    msg: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    match msg {
        WM_HOTKEY_EVENT => {
            if let Some(event) = HotkeyEvent::from_wparam(wparam.0) {
                with_app(|app| app.on_hotkey(event));
            }
            LRESULT(0)
        }
        WM_PIPELINE_STAGE => {
            with_app(|app| app.on_stage(wparam.0 as u64, lparam.0));
            LRESULT(0)
        }
        WM_PIPELINE_DONE => {
            // If the app is busy in a nested loop (menu, dialog), try again shortly.
            if with_app(|app| app.on_done(wparam.0 as u64)).is_none() {
                std::thread::sleep(Duration::from_millis(20));
                let _ = PostMessageW(Some(hwnd), WM_PIPELINE_DONE, wparam, lparam);
            }
            LRESULT(0)
        }
        WM_OPEN_SETTINGS => {
            open_settings(hwnd, wparam.0);
            LRESULT(0)
        }
        WM_SETTINGS_SAVED => {
            with_app(|app| app.reload_if_changed(true, false));
            LRESULT(0)
        }
        WM_OVERLAY_CLICKED => {
            with_app(|app| {
                if matches!(app.state, State::Recording(_)) {
                    app.stop_recording();
                }
            });
            LRESULT(0)
        }
        WM_NOTICE => {
            let notices: Vec<_> =
                std::mem::take(&mut *NOTICES.lock().unwrap_or_else(|e| e.into_inner()));
            with_app(|app| {
                for (title, message, kind) in notices {
                    app.notify(&title, &message, kind);
                }
            });
            LRESULT(0)
        }
        WM_TRAY => {
            let event = (lparam.0 & 0xFFFF) as u32;
            // NOTIFYICON_VERSION_4: NIN_SELECT / NIN_KEYSELECT on left click or Enter.
            if event == 0x400 || event == 0x401 {
                open_settings(hwnd, 0);
            } else if event == WM_CONTEXTMENU {
                // Build the menu inside a short borrow, then track it without holding the app.
                if let Some(menu) = with_app(|app| app.build_menu()) {
                    let cmd = menu.track(hwnd);
                    drop(menu);
                    if cmd != 0 {
                        match with_app(|app| app.on_command(cmd)).flatten() {
                            Some(Followup::AskKey(name)) => ask_and_store_key(hwnd, name),
                            Some(Followup::OpenSettings(page)) => open_settings(hwnd, page),
                            None => {}
                        }
                    }
                }
            }
            LRESULT(0)
        }
        WM_TIMER if wparam.0 == MUTE_TIMER => {
            let _ = KillTimer(Some(hwnd), MUTE_TIMER);
            with_app(|app| {
                if let State::Recording(session) = &mut app.state {
                    session.mute = volume::mute_output();
                }
            });
            LRESULT(0)
        }
        WM_CLOSE => {
            let _ = DestroyWindow(hwnd);
            LRESULT(0)
        }
        WM_DESTROY => {
            hotkey::uninstall();
            APP.with(|a| {
                if let Ok(mut guard) = a.try_borrow_mut() {
                    if let Some(mut app) = guard.take() {
                        app.cancel_recording(false);
                        app.tray.remove();
                    }
                }
            });
            PostQuitMessage(0);
            LRESULT(0)
        }
        m if m != 0 && m == TASKBAR_CREATED.with(|t| t.get()) => {
            // Explorer restarted: the tray icon must be added again.
            with_app(|app| {
                let tip = app.tip();
                app.tray.add(&tip);
            });
            LRESULT(0)
        }
        _ => DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}

/// Asks an already running instance to show its dashboard. Returns false if none runs.
pub fn open_settings_in_running_instance(page: usize) -> bool {
    unsafe {
        match FindWindowW(MAIN_CLASS, None) {
            Ok(hwnd) if !hwnd.is_invalid() => {
                // Let the running instance take the foreground.
                let _ = AllowSetForegroundWindow(ASFW_ANY);
                PostMessageW(Some(hwnd), WM_OPEN_SETTINGS, WPARAM(page), LPARAM(0)).is_ok()
            }
            _ => false,
        }
    }
}

/// Runs the tray app; `open_page` shows the dashboard/settings right away.
pub fn run(open_page: Option<usize>) -> Result<(), String> {
    unsafe {
        // Single instance per user session.
        let _mutex = CreateMutexW(None, true, w!("Local\\VoiceInkWindowsSingleInstance"))
            .map_err(|e| e.to_string())?;
        if GetLastError() == ERROR_ALREADY_EXISTS {
            if open_settings_in_running_instance(open_page.unwrap_or(0)) {
                return Ok(());
            }
            return Err(
                "VoiceInk is already running — look for its icon in the notification area.".into(),
            );
        }

        let _ = SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
        let _ = CoInitializeEx(None, COINIT_APARTMENTTHREADED);

        let config_existed = config::config_path().exists();
        let config = Config::load(&config::config_path())?;

        let instance = GetModuleHandleW(None).map_err(|e| e.to_string())?;
        let class = MAIN_CLASS;
        let wc = WNDCLASSW {
            lpfnWndProc: Some(wnd_proc),
            hInstance: instance.into(),
            lpszClassName: class,
            ..Default::default()
        };
        RegisterClassW(&wc);
        // A hidden top-level window (not message-only) so it receives the
        // TaskbarCreated broadcast and can own the tray icon and menus.
        let hwnd = CreateWindowExW(
            Default::default(),
            class,
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
        .map_err(|e| format!("main window: {e}"))?;
        TASKBAR_CREATED.with(|t| t.set(RegisterWindowMessageW(w!("TaskbarCreated"))));

        let overlay = Overlay::create(hwnd, config.overlay)?;
        let mut tray = Tray::new(hwnd);
        tray.add("VoiceInk");

        let app = App {
            hwnd,
            config,
            config_mtime: config_mtime(),
            tray,
            overlay,
            state: State::Idle,
            next_job: 0,
            last_external: HWND::default(),
            canceled_jobs: HashMap::new(),
        };
        APP.with(|a| *a.borrow_mut() = Some(app));

        let _win_event = SetWinEventHook(
            EVENT_SYSTEM_FOREGROUND,
            EVENT_SYSTEM_FOREGROUND,
            None,
            Some(foreground_changed),
            0,
            0,
            WINEVENT_OUTOFCONTEXT,
        );

        with_app(|app| {
            app.apply_config();
            if app.config.start_with_windows != autostart::is_enabled() {
                let _ = autostart::set_enabled(app.config.start_with_windows);
            }
            let provider = app.config.transcription.provider;
            if provider.requires_api_key() && !credentials::has(provider.key_name()) {
                app.notify(
                    "Almost ready",
                    &format!(
                        "Add your {} API key: click the VoiceInk tray icon › Transcription.",
                        provider.display_name()
                    ),
                    NoticeKind::Warning,
                );
            } else if !config_existed {
                app.notify(
                    "VoiceInk is running",
                    &format!(
                        "Press {} to dictate.",
                        hotkey::describe(&app.config.hotkeys)
                    ),
                    NoticeKind::Info,
                );
            }
        });
        log::info!("ready; settings at {}", config::config_path().display());
        if let Some(page) = open_page {
            open_settings(hwnd, page);
        }

        let mut msg = MSG::default();
        while GetMessageW(&mut msg, None, 0, 0).as_bool() {
            // Tab / Enter / Esc navigation inside the settings window.
            if let Some(dialog) = settings::hwnd() {
                if IsDialogMessageW(dialog, &msg).as_bool() {
                    continue;
                }
            }
            let _ = TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    }
    Ok(())
}
