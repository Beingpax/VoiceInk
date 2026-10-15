//! Pipeline behaviour against fake providers (no network).

use super::*;
use crate::config::{EnhancementProvider, ModeConfig};
use crate::text::{Snippet, WordReplacement};
use chrono::TimeZone;
use std::sync::Mutex;

/// Scripted transcript and chat answers; records every chat request.
#[derive(Default)]
struct Fake {
    transcript: Option<Result<String, String>>,
    chat: Option<Result<String, String>>,
    chat_requests: Arc<Mutex<Vec<(String, String)>>>,
}

impl Fake {
    fn new(transcript: &str) -> Self {
        Self { transcript: Some(Ok(transcript.into())), ..Self::default() }
    }

    fn with_chat(mut self, answer: Result<&str, &str>) -> Self {
        self.chat = Some(answer.map(Into::into).map_err(Into::into));
        self
    }

    fn requests(&self) -> Vec<(String, String)> {
        self.chat_requests.lock().unwrap().clone()
    }
}

struct FakeTranscriber(Result<String, String>);

impl Transcriber for FakeTranscriber {
    fn describe(&self) -> String {
        "Fake whisper".into()
    }
    fn transcribe(&self, _: &TranscriptionRequest<'_>) -> Result<String, TranscriptionError> {
        self.0.clone().map_err(TranscriptionError::NotConfigured)
    }
}

struct FakeChat {
    answer: Result<String, String>,
    requests: Arc<Mutex<Vec<(String, String)>>>,
}

impl ChatModel for FakeChat {
    fn complete(&self, system: &str, user: &str) -> Result<String, EnhancementError> {
        self.requests.lock().unwrap().push((system.into(), user.into()));
        self.answer.clone().map_err(|e| crate::http::HttpError::Network(e).into())
    }
}

impl Services for Fake {
    fn transcriber(&self, _: &TranscriptionSettings) -> Result<Box<dyn Transcriber>, TranscriptionError> {
        match &self.transcript {
            Some(t) => Ok(Box::new(FakeTranscriber(t.clone()))),
            None => Err(TranscriptionError::MissingApiKey("Fake")),
        }
    }

    fn chat_model(
        &self,
        _: &EnhancementSettings,
        provider: EnhancementProvider,
        _: &str,
    ) -> Result<Box<dyn ChatModel>, EnhancementError> {
        match &self.chat {
            Some(answer) => {
                Ok(Box::new(FakeChat { answer: answer.clone(), requests: Arc::clone(&self.chat_requests) }))
            }
            None => Err(EnhancementError::NotConfigured(format!("no key for {}", provider.display_name()))),
        }
    }

    fn now(&self) -> DateTime<Local> {
        Local.with_ymd_and_hms(2026, 10, 15, 9, 30, 0).unwrap()
    }
}

fn config() -> Config {
    let mut cfg = Config::default();
    cfg.enhancement.enabled = true;
    cfg.replacements = vec![WordReplacement { original: "voice ink".into(), replacement: "VoiceInk".into() }];
    cfg
}

fn input() -> PipelineInput {
    PipelineInput { samples: vec![0.0; 16_000], ..PipelineInput::default() }
}

fn command_input(selection: Option<&str>) -> PipelineInput {
    PipelineInput { selected_text: selection.map(Into::into), command: true, ..input() }
}

fn run(cfg: &Config, services: &Fake, input: &PipelineInput) -> (PipelineOutput, Vec<Stage>) {
    let stages = Mutex::new(Vec::new());
    let out = Pipeline::new(cfg, services, &AtomicBool::new(false), &|s| stages.lock().unwrap().push(s)).run(input);
    (out, stages.into_inner().unwrap())
}

#[test]
fn dictation_cleans_and_enhances() {
    let fake = Fake::new("Um, hello [MUSIC] voice ink.").with_chat(Ok("<think>x</think>Hello, VoiceInk!"));
    let (out, stages) = run(&config(), &fake, &input());

    assert!(out.error.is_none());
    assert_eq!(stages, [Stage::Transcribing, Stage::Enhancing]);
    assert_eq!(out.entry.text, "hello VoiceInk.");
    assert_eq!(out.entry.enhanced_text.as_deref(), Some("Hello, VoiceInk!"));
    assert_eq!(out.entry.transcription_model, "Fake whisper");
    assert!((out.entry.duration - 1.0).abs() < 1e-9);
    assert_eq!(out.delivery.unwrap().text, "Hello, VoiceInk!");
    let (system, user) = &fake.requests()[0];
    assert!(system.starts_with("<SYSTEM_INSTRUCTIONS>"));
    assert_eq!(user, "\n<TRANSCRIPT>\nhello VoiceInk.\n</TRANSCRIPT>");
}

#[test]
fn transcription_failure_is_reported() {
    let fake = Fake { transcript: None, ..Fake::default() };
    let (out, _) = run(&config(), &fake, &input());
    assert_eq!(out.entry.status, Status::Failed);
    assert!(out.error.unwrap().contains("Fake"));
    assert!(out.entry.text.starts_with("Transcription Failed"));
    assert!(out.delivery.is_none());
}

#[test]
fn enhancement_failure_still_delivers_the_transcript() {
    let fake = Fake::new("plain words here").with_chat(Err("bad model"));
    let (out, _) = run(&config(), &fake, &input());
    assert_eq!(out.entry.status, Status::Completed);
    assert_eq!(out.entry.enhanced_text, None);
    assert!(out.entry.enhancement_error.as_deref().unwrap().contains("bad model"));
    assert!(out.warning.unwrap().starts_with("Enhancement failed"));
    assert_eq!(out.delivery.unwrap().text, "plain words here");
}

#[test]
fn unconfigured_enhancement_warns_and_skips() {
    let fake = Fake::new("hello");
    let (out, stages) = run(&config(), &fake, &input());
    assert_eq!(stages, [Stage::Transcribing]);
    assert!(out.warning.unwrap().contains("not configured"));
    assert_eq!(out.delivery.unwrap().text, "hello");
}

#[test]
fn cancel_before_start_does_nothing() {
    let fake = Fake::new("never");
    let out = Pipeline::new(&config(), &fake, &AtomicBool::new(true), &|_| panic!("no stage expected")).run(&input());
    assert_eq!(out.entry.status, Status::Canceled);
    assert!(out.delivery.is_none());
}

#[test]
fn trigger_word_switches_mode() {
    let mut cfg = config();
    cfg.enhancement.enabled = false;
    cfg.modes = vec![ModeConfig {
        name: "Email".into(),
        trigger_words: vec!["email".into()],
        send_key: Some(SendKey::Enter),
        ..ModeConfig::default()
    }];
    let (out, _) = run(&cfg, &Fake::new("Email, hi there"), &input());
    assert_eq!(out.entry.mode_name.as_deref(), Some("Email"));
    let delivery = out.delivery.unwrap();
    assert_eq!(delivery.text, "Hi there");
    assert_eq!(delivery.send_key, SendKey::Enter);
}

#[test]
fn exact_snippet_skips_enhancement() {
    let mut cfg = config();
    cfg.snippets = vec![Snippet { trigger: "today".into(), text: "Date: {date}".into() }];
    let fake = Fake::new("Today.").with_chat(Ok("unused"));
    let (out, stages) = run(&cfg, &fake, &input());
    assert_eq!(stages, [Stage::Transcribing]);
    assert_eq!(fake.requests(), vec![]);
    assert_eq!(out.delivery.unwrap().text, "Date: 2026-10-15");
    assert_eq!(out.entry.final_text(), "Date: 2026-10-15");
}

#[test]
fn inline_snippet_expands_after_enhancement() {
    let mut cfg = config();
    cfg.snippets = vec![Snippet { trigger: "my calendar link".into(), text: "https://cal.example.com/me".into() }];
    let fake = Fake::new("book via my calendar link").with_chat(Ok("Book via my calendar link."));
    let (out, _) = run(&cfg, &fake, &input());
    assert_eq!(out.entry.enhanced_text.as_deref(), Some("Book via my calendar link."));
    assert_eq!(out.delivery.unwrap().text, "Book via https://cal.example.com/me.");
}

#[test]
fn command_mode_edits_selection_even_with_enhancement_off() {
    let mut cfg = config();
    cfg.enhancement.enabled = false;
    let fake = Fake::new("Make this more formal.").with_chat(Ok("Good afternoon, how are you?"));
    let (out, stages) = run(&cfg, &fake, &command_input(Some("hey whats up")));

    assert!(out.error.is_none());
    assert_eq!(stages, [Stage::Transcribing, Stage::Enhancing]);
    assert_eq!(out.entry.mode_name.as_deref(), Some("Command"));
    assert_eq!(out.entry.final_text(), "Good afternoon, how are you?");
    assert_eq!(out.delivery.unwrap(), Delivery::paste("Good afternoon, how are you?".into()));
    let (_, user) = &fake.requests()[0];
    assert_eq!(
        user,
        "<SELECTED_TEXT>\nhey whats up\n</SELECTED_TEXT>\n\n<INSTRUCTION>\nMake this more formal.\n</INSTRUCTION>"
    );
}

#[test]
fn command_failures_paste_nothing() {
    let failing = Fake::new("translate to German").with_chat(Err("overloaded"));
    let (out, _) = run(&config(), &failing, &command_input(Some("hello")));
    assert!(out.delivery.is_none());
    assert_eq!(out.entry.status, Status::Failed);
    assert!(out.error.unwrap().starts_with("Command failed"));

    let unconfigured = Fake::new("translate");
    let (out, _) = run(&config(), &unconfigured, &command_input(Some("hello")));
    assert!(out.error.unwrap().contains("needs an AI provider"));

    let silent = Fake::new("[MUSIC]").with_chat(Ok("unused"));
    let (out, _) = run(&config(), &silent, &command_input(None));
    assert_eq!(out.error.as_deref(), Some("No instruction was recognized."));
}

#[test]
fn window_context_format() {
    let fg = ForegroundInfo { process_name: "code.exe".into(), window_title: "main.rs".into() };
    assert_eq!(dictation::window_context(&fg).unwrap(), "Application: code.exe\nWindow title: main.rs");
    assert!(dictation::window_context(&ForegroundInfo::default()).is_none());
}
