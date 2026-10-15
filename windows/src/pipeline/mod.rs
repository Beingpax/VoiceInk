//! Post-recording pipeline, ported from `TranscriptionPipeline.swift`.
//!
//! * Dictation: transcribe → filter → trigger words → format → replacements →
//!   snippets → AI enhancement → inline snippet expansion.
//! * Command Mode: transcribe → instruction + selected text → LLM.
//!
//! The pipeline is platform independent and talks to providers only through
//! [`Services`], so tests run it against fakes. The caller performs delivery
//! (paste / custom command) and persists the history entry.

mod command;
mod dictation;
#[cfg(test)]
mod tests;

use crate::audio::{TARGET_SAMPLE_RATE, duration_secs, wav};
use crate::config::{Config, EnhancementProvider, EnhancementSettings, OutputMode, SendKey, TranscriptionSettings};
use crate::credentials::Secrets;
use crate::enhancement::{self, ChatModel, EnhancementError, RateLimiter};
use crate::history::{Entry, Status};
use crate::modes::ForegroundInfo;
use crate::transcription::{self, Transcriber, TranscriptionError, TranscriptionRequest};
use chrono::{DateTime, Local};
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Instant;

/// Progress reported while the pipeline runs.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Stage {
    Transcribing,
    Enhancing,
}

#[derive(Debug, Default, Clone)]
pub struct PipelineInput {
    /// 16 kHz mono samples.
    pub samples: Vec<f32>,
    pub foreground: ForegroundInfo,
    pub clipboard_text: Option<String>,
    pub selected_text: Option<String>,
    /// Command Mode: the recording is an instruction for `selected_text`.
    pub command: bool,
}

/// What should happen with the final text.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Delivery {
    pub text: String,
    pub output: OutputMode,
    pub custom_command: Option<String>,
    pub send_key: SendKey,
}

impl Delivery {
    /// Plain paste at the cursor.
    pub fn paste(text: String) -> Self {
        Self { text, output: OutputMode::Paste, custom_command: None, send_key: SendKey::None }
    }
}

#[derive(Debug, Clone)]
pub struct PipelineOutput {
    pub entry: Entry,
    pub delivery: Option<Delivery>,
    /// A non-fatal problem worth showing to the user (e.g. enhancement failed).
    pub warning: Option<String>,
    /// A fatal problem (transcription or Command Mode failed).
    pub error: Option<String>,
}

/// Everything the pipeline needs from the outside world.
pub trait Services: Send + Sync {
    /// # Errors
    /// Returns [`TranscriptionError`] when the provider is not configured.
    fn transcriber(&self, settings: &TranscriptionSettings) -> Result<Box<dyn Transcriber>, TranscriptionError>;

    /// # Errors
    /// Returns [`EnhancementError::NotConfigured`] when the provider lacks a key or endpoint.
    fn chat_model(
        &self,
        settings: &EnhancementSettings,
        provider: EnhancementProvider,
        model: &str,
    ) -> Result<Box<dyn ChatModel>, EnhancementError>;

    fn now(&self) -> DateTime<Local> {
        Local::now()
    }
}

/// Real providers, keys from the secret store.
pub struct LiveServices {
    secrets: Secrets,
    models_dir: PathBuf,
    limiter: Arc<RateLimiter>,
}

impl LiveServices {
    pub fn new(secrets: Secrets, models_dir: PathBuf) -> Self {
        Self { secrets, models_dir, limiter: Arc::new(RateLimiter::default()) }
    }
}

impl Services for LiveServices {
    fn transcriber(&self, settings: &TranscriptionSettings) -> Result<Box<dyn Transcriber>, TranscriptionError> {
        transcription::create(settings, self.secrets.as_ref(), &self.models_dir)
    }

    fn chat_model(
        &self,
        settings: &EnhancementSettings,
        provider: EnhancementProvider,
        model: &str,
    ) -> Result<Box<dyn ChatModel>, EnhancementError> {
        enhancement::create(settings, provider, model, self.secrets.as_ref(), &self.limiter)
    }
}

/// Why a run ended early.
enum Stop {
    Canceled,
    Failed(String),
}

/// Successful end of a run.
struct Finished {
    delivery: Option<Delivery>,
    warning: Option<String>,
}

/// One pipeline run over a recording.
pub struct Pipeline<'a> {
    config: &'a Config,
    services: &'a dyn Services,
    cancel: &'a AtomicBool,
    on_stage: &'a dyn Fn(Stage),
}

impl<'a> Pipeline<'a> {
    pub fn new(
        config: &'a Config,
        services: &'a dyn Services,
        cancel: &'a AtomicBool,
        on_stage: &'a dyn Fn(Stage),
    ) -> Self {
        Self { config, services, cancel, on_stage }
    }

    pub fn run(&self, input: &PipelineInput) -> PipelineOutput {
        let mut entry = Entry::new(Status::Completed);
        entry.duration = duration_secs(input.samples.len(), TARGET_SAMPLE_RATE);
        entry.app = Some(input.foreground.process_name.clone()).filter(|p| !p.is_empty());

        let result =
            if input.command { self.run_command(input, &mut entry) } else { self.run_dictation(input, &mut entry) };

        match result {
            Ok(Finished { delivery, warning }) => PipelineOutput { entry, delivery, warning, error: None },
            Err(Stop::Canceled) => {
                entry.status = Status::Canceled;
                PipelineOutput { entry, delivery: None, warning: None, error: None }
            }
            Err(Stop::Failed(message)) => {
                entry.status = Status::Failed;
                PipelineOutput { entry, delivery: None, warning: None, error: Some(message) }
            }
        }
    }

    fn check_cancel(&self) -> Result<(), Stop> {
        if self.cancel.load(Ordering::SeqCst) { Err(Stop::Canceled) } else { Ok(()) }
    }

    /// Transcribes and filters the recording (shared by both flows).
    fn transcribe(&self, input: &PipelineInput, language: Option<&str>, entry: &mut Entry) -> Result<String, Stop> {
        self.check_cancel()?;
        (self.on_stage)(Stage::Transcribing);
        let settings = &self.config.transcription;
        entry.transcription_model = format!("{} {}", settings.provider.display_name(), settings.model_name());

        let started = Instant::now();
        let result = self.services.transcriber(settings).and_then(|transcriber| {
            entry.transcription_model = transcriber.describe();
            let wav = wav::encode_wav_i16(&input.samples, TARGET_SAMPLE_RATE);
            transcriber.transcribe(&TranscriptionRequest {
                wav: &wav,
                samples: &input.samples,
                language,
                vocabulary: &self.config.vocabulary,
            })
        });
        entry.transcription_secs = started.elapsed().as_secs_f64();

        let raw = result.map_err(|e| {
            entry.text = format!("Transcription Failed: {e}");
            Stop::Failed(e.to_string())
        })?;
        self.check_cancel()?;

        Ok(if settings.filter_output {
            crate::text::filter_transcription(&raw, &self.config.filler_words)
        } else {
            raw.trim().to_string()
        })
    }
}
