//! The application state machine: idle → recording → processing.
//!
//! Shortcut events are turned into decisions by the portable
//! [`RecordingPolicy`]; this type carries them out with the Win32 services
//! (capture, overlay, tray) and hands recordings to the pipeline on a worker
//! thread.

use super::super::capture::Recorder;
use super::super::icon::IconState;
use super::super::overlay::{Overlay, View};
use super::super::sound::{self, Cue};
use super::super::tray::{Menu, NoticeKind, Tray};
use super::super::{actions, autostart, clipboard, foreground, hotkey, paste, volume};
use super::config_file::ConfigFile;
use super::delivery;
use super::events::{JobId, Notice, SendHwnd, UiEvent, UiSender};
use super::menu::{self, MenuAction, MenuState};
use super::ui_link::UiLink;
use crate::APP_VERSION;
use crate::config::SettingChange;
use crate::context::AppContext;
use crate::input::{Decision, HotkeyEvent, Phase, RecordingPolicy, TriggerKind};
use crate::modes::{self, ForegroundInfo};
use crate::pipeline::{Delivery, Pipeline, PipelineInput, Stage};
use crate::settings_page::SettingsPage;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Receiver};
use std::time::{Duration, Instant};
use windows::Win32::Foundation::HWND;
use windows::Win32::UI::WindowsAndMessaging::{KillTimer, SetTimer};

/// Timer that mutes system audio shortly after recording starts (so the
/// start sound is still audible).
pub const MUTE_TIMER: usize = 10;
const MUTE_DELAY_MS: u32 = 250;
/// How long to wait for the selection copied at recording start.
const COMMAND_SELECTION_WAIT: Duration = Duration::from_millis(600);
const CONTEXT_SELECTION_WAIT: Duration = Duration::from_millis(50);
const ERROR_BANNER: Duration = Duration::from_secs(3);

struct Recording {
    recorder: Recorder,
    kind: TriggerKind,
    /// The current key press started this recording (it may end on release).
    started_by_press: bool,
    /// Where the text goes.
    target: HWND,
    foreground: ForegroundInfo,
    clipboard_text: Option<String>,
    /// The selection, copied on a worker thread when recording starts.
    selection: Option<Receiver<Option<String>>>,
    mute: Option<volume::MuteGuard>,
}

struct Job {
    id: JobId,
    kind: TriggerKind,
    cancel: Arc<AtomicBool>,
    target: HWND,
}

enum State {
    Idle,
    Recording(Box<Recording>),
    Processing(Job),
}

pub struct App {
    hwnd: HWND,
    ctx: AppContext,
    config: ConfigFile,
    tray: Tray,
    overlay: Overlay,
    state: State,
    last_job: JobId,
    /// Last focused window that isn't `VoiceInk` or the taskbar: the target for
    /// recordings started from the tray menu.
    last_external: HWND,
    events: UiSender,
    inbox: Receiver<UiEvent>,
    /// The Dashboard & Settings window.
    ui: UiLink,
}

impl App {
    pub fn new(
        hwnd: HWND,
        ctx: AppContext,
        config: ConfigFile,
        overlay: Overlay,
        (events, inbox): (UiSender, Receiver<UiEvent>),
    ) -> Self {
        let mut tray = Tray::new(hwnd);
        tray.add("VoiceInk");
        Self {
            hwnd,
            ctx,
            config,
            tray,
            overlay,
            state: State::Idle,
            last_job: 0,
            last_external: HWND::default(),
            events,
            inbox,
            ui: UiLink::default(),
        }
    }

    pub fn ui(&mut self) -> &mut UiLink {
        &mut self.ui
    }

    // -- configuration ------------------------------------------------------

    /// Installs hotkeys and options from the current configuration.
    pub fn apply_config(&mut self) {
        let config = self.config.get();
        let command = config.command.enabled.then_some(config.command.hotkey.as_str());
        match hotkey::install(self.hwnd, &config.hotkeys, command) {
            Ok(problems) if !problems.is_empty() => {
                let text: Vec<String> = problems.iter().map(ToString::to_string).collect();
                self.notify(&Notice::new("Shortcut problem", text.join("\n"), NoticeKind::Warning));
            }
            Ok(_) => {}
            Err(e) => self.notify(&Notice::new("Shortcuts unavailable", e.to_string(), NoticeKind::Error)),
        }
        self.overlay.set_position(self.config.get().overlay);
        self.sync_autostart();
        self.refresh_tray();
    }

    fn sync_autostart(&self) {
        let wanted = self.config.get().start_with_windows;
        if wanted != autostart::is_enabled()
            && let Err(e) = autostart::set_enabled(wanted)
        {
            self.notify(&Notice::new("Could not change autostart", e.to_string(), NoticeKind::Error));
        }
    }

    /// Picks up changes to `config.json` (from the settings window or by hand).
    pub fn reload_config(&mut self, force: bool, announce: bool) {
        match self.config.reload(force) {
            Ok(true) => {
                self.apply_config();
                if announce {
                    self.notify(&Notice::new("Settings reloaded", "", NoticeKind::Info));
                }
            }
            Ok(false) => {}
            Err(e) => self.notify(&Notice::new("Settings file has an error", e.to_string(), NoticeKind::Error)),
        }
    }

    fn change_setting(&mut self, change: &SettingChange) {
        if let Err(e) = self.config.update(|config| change.apply(config)) {
            self.notify(&Notice::new("Could not save settings", e.to_string(), NoticeKind::Error));
        }
        if change.affects_hotkeys() {
            self.apply_config();
        }
    }

    /// Tells the user on startup what is still missing.
    pub fn greet(&self, first_run: bool) {
        let config = self.config.get();
        let provider = config.transcription.provider;
        if provider.credential_key().is_some_and(|key| !self.ctx.secrets.has(key)) {
            let message =
                format!("Add your {} API key: click the VoiceInk tray icon › API keys.", provider.display_name());
            self.notify(&Notice::new("Almost ready", message, NoticeKind::Warning));
        } else if first_run {
            let message = format!("Press {} to dictate.", config.hotkeys.describe());
            self.notify(&Notice::new("VoiceInk is running", message, NoticeKind::Info));
        }
    }

    // -- tray ---------------------------------------------------------------

    fn tip(&self) -> String {
        let status = match self.state {
            State::Idle => "Ready",
            State::Recording(_) => "Recording…",
            State::Processing(_) => "Processing…",
        };
        format!("VoiceInk — {status}\n{}", self.config.get().hotkeys.record)
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

    /// Re-adds the tray icon after Explorer restarted.
    pub fn restore_tray_icon(&mut self) {
        let tip = self.tip();
        self.tray.add(&tip);
    }

    pub fn notify(&self, notice: &Notice) {
        log::info!("notice: {}: {}", notice.title, notice.message);
        self.tray.notify(&notice.title, &notice.message, notice.kind);
    }

    // -- events -------------------------------------------------------------

    /// Remembers the last focused window of another application.
    pub fn foreground_changed(&mut self, hwnd: HWND) {
        if !foreground::is_own_or_shell(hwnd) {
            self.last_external = hwnd;
        }
    }

    pub fn on_hotkey(&mut self, event: HotkeyEvent) {
        let hotkeys = &self.config.get().hotkeys;
        let policy =
            RecordingPolicy { mode: hotkeys.mode, hold_threshold: Duration::from_millis(hotkeys.hybrid_threshold_ms) };
        match policy.decide(self.phase(), event) {
            Decision::Start(kind) => self.start_recording(kind, true),
            Decision::Stop => self.stop_recording(),
            Decision::KeepRecording => {
                if let State::Recording(recording) = &mut self.state {
                    recording.started_by_press = false;
                }
            }
            Decision::CancelRecording { audible } => self.cancel_recording(audible),
            Decision::CancelProcessing => self.cancel_job(),
            Decision::PasteLast => self.paste_last(),
            Decision::Ignore => {}
        }
    }

    fn phase(&self) -> Phase {
        match &self.state {
            State::Idle => Phase::Idle,
            State::Recording(r) => {
                Phase::Recording { kind: r.kind, started_by_press: r.started_by_press, elapsed: r.recorder.elapsed() }
            }
            State::Processing(_) => Phase::Processing,
        }
    }

    /// Handles everything worker threads queued.
    pub fn drain_events(&mut self) {
        while let Ok(event) = self.inbox.try_recv() {
            match event {
                UiEvent::Stage { job, stage } => self.on_stage(job, stage),
                UiEvent::Finished { job, output } => self.on_finished(job, *output),
                UiEvent::Notice(notice) => self.notify(&notice),
            }
        }
    }

    pub fn overlay_clicked(&mut self) {
        if matches!(self.state, State::Recording(_)) {
            self.stop_recording();
        }
    }

    pub fn mute_timer_elapsed(&mut self) {
        // SAFETY: our own window and timer.
        let _ = unsafe { KillTimer(Some(self.hwnd), MUTE_TIMER) };
        if let State::Recording(recording) = &mut self.state {
            recording.mute = volume::mute_output();
        }
    }

    // -- recording ----------------------------------------------------------

    /// The window that receives the text, plus what modes match against.
    fn paste_target(&self) -> (HWND, ForegroundInfo) {
        let (target, info) = foreground::current();
        if !foreground::is_own_or_shell(target) || self.last_external.is_invalid() {
            return (target, info);
        }
        // Started from the tray: go back to the app the user was in.
        let target = self.last_external;
        foreground::restore_focus(target);
        (
            target,
            ForegroundInfo {
                process_name: foreground::process_name(target),
                window_title: foreground::window_title(target),
            },
        )
    }

    fn start_recording(&mut self, kind: TriggerKind, by_press: bool) {
        self.reload_config(false, false);
        let (target, foreground) = self.paste_target();
        let config = self.config.get();
        let resolved = modes::resolve(config, modes::match_mode(&config.modes, &foreground));
        let clipboard_text = resolved.use_clipboard_context.then(clipboard::get_text).flatten();
        let audio = &config.audio;
        if audio.play_sounds {
            sound::play(Cue::Start, audio.start_sound.as_deref());
        }
        let recorder = match Recorder::start(audio.input_device.clone()) {
            Ok(recorder) => recorder,
            Err(e) => {
                log::error!("recording failed to start: {e}");
                return self.notify(&Notice::new("Could not start recording", e.to_string(), NoticeKind::Error));
            }
        };

        // Command Mode always needs the selection; dictation only as AI context.
        let command = kind == TriggerKind::Command;
        let selection = (command || resolved.use_selected_text_context).then(copy_selection_in_background);
        let mode = if command { Some("Command".to_string()) } else { resolved.mode_name.clone() };
        self.overlay.show(View::Recording { started: Instant::now(), level: recorder.level_handle(), mode });
        if audio.mute_system_audio {
            // SAFETY: our own window; the timer is killed when it fires or recording stops.
            unsafe { SetTimer(Some(self.hwnd), MUTE_TIMER, MUTE_DELAY_MS, None) };
        }
        self.state = State::Recording(Box::new(Recording {
            recorder,
            kind,
            started_by_press: by_press,
            target,
            foreground,
            clipboard_text,
            selection,
            mute: None,
        }));
        self.refresh_tray();
    }

    /// Leaves the recording state, restoring audio output.
    fn take_recording(&mut self) -> Option<Recording> {
        let State::Recording(recording) = std::mem::replace(&mut self.state, State::Idle) else { return None };
        // SAFETY: our own window and timer.
        let _ = unsafe { KillTimer(Some(self.hwnd), MUTE_TIMER) };
        let mut recording = *recording;
        recording.mute = None;
        Some(recording)
    }

    fn cancel_recording(&mut self, audible: bool) {
        if let Some(recording) = self.take_recording() {
            recording.recorder.cancel();
            if audible && self.config.get().audio.play_sounds {
                sound::play(Cue::Cancel, None);
            }
        }
        self.back_to_idle();
    }

    fn back_to_idle(&mut self) {
        self.state = State::Idle;
        self.overlay.hide();
        self.refresh_tray();
    }

    fn stop_recording(&mut self) {
        let Some(recording) = self.take_recording() else { return };
        let elapsed = recording.recorder.elapsed();
        let samples = match recording.recorder.finish() {
            Ok(samples) => samples,
            Err(e) => {
                self.notify(&Notice::new("Recording failed", e.to_string(), NoticeKind::Error));
                return self.back_to_idle();
            }
        };
        let audio = &self.config.get().audio;
        if audio.play_sounds {
            sound::play(Cue::Stop, audio.stop_sound.as_deref());
        }
        if samples.is_empty() || elapsed < Duration::from_millis(audio.min_recording_ms) {
            return self.back_to_idle();
        }

        let command = recording.kind == TriggerKind::Command;
        let wait = if command { COMMAND_SELECTION_WAIT } else { CONTEXT_SELECTION_WAIT };
        let selected_text = recording.selection.and_then(|rx| rx.recv_timeout(wait).ok()).flatten();
        let input = PipelineInput {
            samples,
            foreground: recording.foreground,
            clipboard_text: recording.clipboard_text,
            selected_text,
            command,
        };
        self.start_job(input, recording.target, recording.kind);
    }

    // -- processing ---------------------------------------------------------

    fn start_job(&mut self, input: PipelineInput, target: HWND, kind: TriggerKind) {
        self.last_job += 1;
        let id = self.last_job;
        let cancel = Arc::new(AtomicBool::new(false));
        self.state = State::Processing(Job { id, kind, cancel: Arc::clone(&cancel), target });
        self.overlay.show(View::Transcribing);
        self.refresh_tray();

        let config = self.config.get().clone();
        let ctx = self.ctx.clone();
        let events = self.events.clone();
        let spawned = std::thread::Builder::new().name(format!("voiceink-job-{id}")).spawn(move || {
            let on_stage = |stage| events.send(UiEvent::Stage { job: id, stage });
            let mut output = Pipeline::new(&config, ctx.services.as_ref(), &cancel, &on_stage).run(&input);
            if cancel.load(Ordering::SeqCst) {
                output.entry.status = crate::history::Status::Canceled;
                output.delivery = None;
            }
            if let Err(e) = ctx.history.record(&config.history, output.entry.clone(), &input.samples) {
                log::warn!("history write failed: {e}");
            }
            events.send(UiEvent::Finished { job: id, output: Box::new(output) });
        });
        if let Err(e) = spawned {
            self.notify(&Notice::new("Transcription failed", e.to_string(), NoticeKind::Error));
            self.back_to_idle();
        }
    }

    fn cancel_job(&mut self) {
        if let State::Processing(job) = &self.state {
            job.cancel.store(true, Ordering::SeqCst);
            if self.config.get().audio.play_sounds {
                sound::play(Cue::Cancel, None);
            }
        }
        self.back_to_idle();
    }

    fn current_job(&self, id: JobId) -> bool {
        matches!(&self.state, State::Processing(job) if job.id == id)
    }

    fn on_stage(&mut self, id: JobId, stage: Stage) {
        if self.current_job(id) {
            self.overlay.show(match stage {
                Stage::Transcribing => View::Transcribing,
                Stage::Enhancing => View::Enhancing,
            });
        }
    }

    fn on_finished(&mut self, id: JobId, output: crate::pipeline::PipelineOutput) {
        self.ui.history_changed();
        // A canceled (or superseded) job's result is dropped.
        if !self.current_job(id) {
            return;
        }
        let State::Processing(job) = std::mem::replace(&mut self.state, State::Idle) else { return };
        match &output.error {
            Some(error) => {
                let title = match job.kind {
                    TriggerKind::Command => "Command failed",
                    TriggerKind::Dictation => "Transcription failed",
                };
                self.overlay.show(View::Message { text: title.into(), until: Instant::now() + ERROR_BANNER });
                self.notify(&Notice::new(title, error.clone(), NoticeKind::Error));
            }
            None => self.overlay.hide(),
        }
        if let Some(warning) = output.warning {
            self.notify(&Notice::new("VoiceInk", warning, NoticeKind::Warning));
        }
        if let Some(delivery) = output.delivery {
            self.deliver(delivery, job.target);
        }
        self.refresh_tray();
    }

    fn deliver(&self, delivery: Delivery, target: HWND) {
        let output = self.config.get().output.clone();
        delivery::deliver(delivery, SendHwnd::new(target), output, self.events.clone());
    }

    fn paste_last(&self) {
        match self.ctx.history.last_text() {
            // The focused window is the target: nothing to restore.
            Some(text) => self.deliver(Delivery::paste(text), HWND::default()),
            None => self.notify(&Notice::new("Nothing to paste", "There is no transcription yet.", NoticeKind::Info)),
        }
    }

    // -- menu ---------------------------------------------------------------

    /// The tray menu for the current state.
    pub fn menu(&self) -> (Menu, menu::Items) {
        let toggle_label = match self.state {
            State::Idle => "Start recording",
            State::Recording(_) => "Stop recording",
            State::Processing(_) => "Cancel processing",
        };
        menu::build(&MenuState {
            config: self.config.get(),
            secrets: self.ctx.secrets.as_ref(),
            toggle_label,
            autostart: autostart::is_enabled(),
        })
    }

    pub fn on_menu(&mut self, action: MenuAction) {
        match action {
            MenuAction::ToggleRecording => match self.state {
                State::Idle => self.start_recording(TriggerKind::Dictation, false),
                State::Recording(_) => self.stop_recording(),
                State::Processing(_) => self.cancel_job(),
            },
            MenuAction::PasteLast => self.paste_last(),
            MenuAction::OpenSettings(page) => self.ui.open_settings(page),
            MenuAction::Setting(change) => {
                self.change_setting(&change);
                if let Some(key) = change.required_key(self.config.get()).filter(|key| !self.ctx.secrets.has(key)) {
                    log::info!("{key} API key missing; opening settings");
                    let page = if matches!(change, SettingChange::TranscriptionProvider(_)) {
                        SettingsPage::Transcription
                    } else {
                        SettingsPage::Enhancement
                    };
                    self.ui.open_settings(page);
                }
            }
            MenuAction::ToggleAutostart => {
                let enable = !autostart::is_enabled();
                if let Err(e) = self.config.update(|config| config.start_with_windows = enable) {
                    self.notify(&Notice::new("Could not save settings", e.to_string(), NoticeKind::Error));
                }
                self.sync_autostart();
            }
            MenuAction::OpenConfigFile => actions::open_config_file(&self.ctx),
            MenuAction::ReloadConfig => self.reload_config(true, true),
            MenuAction::OpenHistoryCsv => {
                if let Err(e) = actions::open_history_csv(&self.ctx) {
                    self.notify(&Notice::new("Could not export history", e.to_string(), NoticeKind::Error));
                }
            }
            MenuAction::OpenDataFolder => actions::open_data_folder(&self.ctx),
            MenuAction::About => self.notify(&Notice::new(
                format!("VoiceInk for Windows {APP_VERSION}"),
                "Voice to text in any app. Press your shortcut, speak, and the text is pasted where your cursor is.",
                NoticeKind::Info,
            )),
            MenuAction::Quit => self.ui.quit(),
        }
        self.refresh_tray();
    }

    /// Stops everything before the window goes away.
    pub fn shutdown(&mut self) {
        if let State::Processing(job) = &self.state {
            job.cancel.store(true, Ordering::SeqCst);
        }
        self.cancel_recording(false);
        self.tray.remove();
    }
}

/// Copies the selection (Ctrl+C) on a worker thread so recording starts at once.
fn copy_selection_in_background() -> Receiver<Option<String>> {
    let (tx, rx) = mpsc::channel();
    std::thread::spawn(move || {
        let _ = tx.send(paste::copy_selection());
    });
    rx
}
