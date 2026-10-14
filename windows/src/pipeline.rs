//! Post-recording pipeline, ported from `TranscriptionPipeline.swift`:
//! transcribe → filter → trigger words → format → word replacements →
//! snippets → AI enhance → inline snippet expansion.
//!
//! Command Mode recordings take a separate path: the transcript is an
//! instruction that the LLM applies to the selected text (see [`run_command`]).
//!
//! The pipeline is platform independent; the Windows layer feeds it audio and
//! foreground-window context and performs the delivery (paste / command).

use crate::audio::{duration_secs, wav, TARGET_SAMPLE_RATE};
use crate::config::{Config, OutputMode, SendKey};
use crate::enhancement::{self, EnhancementRequest};
use crate::history::{self, Entry, Status};
use crate::modes::{self, ForegroundInfo};
use crate::prompts::PromptContext;
use crate::text;
use crate::transcription::{self, TranscriptionRequest};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Instant;

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

#[derive(Debug, Clone)]
pub struct PipelineOutput {
    pub entry: Entry,
    pub delivery: Option<Delivery>,
    /// A non-fatal problem worth showing to the user (e.g. enhancement failed).
    pub warning: Option<String>,
    /// A fatal problem (transcription failed).
    pub error: Option<String>,
}

fn window_context(fg: &ForegroundInfo) -> Option<String> {
    let mut lines = Vec::new();
    if !fg.process_name.is_empty() {
        lines.push(format!("Application: {}", fg.process_name));
    }
    if !fg.window_title.trim().is_empty() {
        lines.push(format!("Window title: {}", fg.window_title.trim()));
    }
    (!lines.is_empty()).then(|| lines.join("\n"))
}

pub fn run(
    config: &Config,
    input: &PipelineInput,
    cancel: &AtomicBool,
    on_stage: &dyn Fn(Stage),
) -> PipelineOutput {
    let canceled = |mut entry: Entry| {
        entry.status = Status::Canceled;
        PipelineOutput {
            entry,
            delivery: None,
            warning: None,
            error: None,
        }
    };

    let mut entry = Entry::new(Status::Completed);
    entry.duration = duration_secs(input.samples.len(), TARGET_SAMPLE_RATE);
    entry.transcription_model = format!(
        "{} {}",
        config.transcription.provider.display_name(),
        config.transcription.model_name()
    );
    if !input.foreground.process_name.is_empty() {
        entry.app = Some(input.foreground.process_name.clone());
    }

    let mut mode = modes::match_mode(&config.modes, &input.foreground);
    let mut resolved = modes::resolve(config, mode);

    let wav_bytes = wav::encode_wav_i16(&input.samples, TARGET_SAMPLE_RATE);
    if config.history.enabled && config.history.save_audio {
        let dir = history::recordings_dir();
        let path = dir.join(format!("{}.wav", entry.id));
        if std::fs::create_dir_all(&dir)
            .and_then(|_| std::fs::write(&path, &wav_bytes))
            .is_ok()
        {
            entry.audio_file = Some(path);
        }
    }

    if cancel.load(Ordering::SeqCst) {
        return canceled(entry);
    }

    // 1. Transcribe.
    on_stage(Stage::Transcribing);
    let started = Instant::now();
    let request = TranscriptionRequest {
        wav: &wav_bytes,
        samples: &input.samples,
        language: resolved.language.as_deref(),
        vocabulary: &config.vocabulary,
    };
    let raw = match transcription::transcribe(&config.transcription, &request) {
        Ok(t) => t,
        Err(e) => {
            entry.status = Status::Failed;
            entry.text = format!("Transcription Failed: {e}");
            entry.transcription_secs = started.elapsed().as_secs_f64();
            return PipelineOutput {
                entry,
                delivery: None,
                warning: None,
                error: Some(e.to_string()),
            };
        }
    };
    entry.transcription_secs = started.elapsed().as_secs_f64();
    if cancel.load(Ordering::SeqCst) {
        entry.text = raw;
        return canceled(entry);
    }

    // 2. Filter hallucinations and filler words.
    let mut text = if config.transcription.filter_output {
        text::filter_transcription(&raw, &config.filler_words)
    } else {
        raw.trim().to_string()
    };

    if input.command {
        return run_command(config, input, entry, &text, cancel, on_stage);
    }

    // 3. Spoken trigger words switch the mode.
    if let Some(d) = modes::detect_trigger(&text, &config.modes) {
        mode = config.modes.get(d.mode_index);
        resolved = modes::resolve(config, mode);
        text = d.processed_text;
    }

    // 4. Paragraph formatting and 5. dictionary replacements.
    if resolved.text_formatting {
        text = text::format_paragraphs(&text);
    }
    text = text::apply_replacements(&text, &config.replacements);
    entry.text = text.clone();
    entry.mode_name = resolved.mode_name.clone();

    let mut final_text = text.clone();
    let mut warning = None;
    let now = chrono::Local::now();

    // 6. Saying just a snippet's trigger inserts the snippet verbatim.
    let snippet = text::snippets::exact_match(&text, &config.snippets);
    if let Some(snippet) = snippet {
        final_text = text::snippets::render(&snippet.text, now);
        entry.delivered_text = Some(final_text.clone());
    }

    // 7. AI enhancement.
    let skip_short = snippet.is_some()
        || (config.enhancement.skip_short_transcripts
            && text::word_count(&text)
                <= config.enhancement.short_transcript_word_threshold.max(1));
    let prompt = config.active_prompt(Some(&resolved.prompt_id));
    if resolved.enhancement_enabled && !skip_short && !text.is_empty() {
        if let Some(prompt) = prompt {
            if enhancement::is_configured(&config.enhancement, resolved.provider) {
                if cancel.load(Ordering::SeqCst) {
                    return canceled(entry);
                }
                on_stage(Stage::Enhancing);
                let window = resolved
                    .use_window_context
                    .then(|| window_context(&input.foreground))
                    .flatten();
                let request = EnhancementRequest {
                    settings: &config.enhancement,
                    provider: resolved.provider,
                    model: resolved.model.clone(),
                    prompt,
                    context: PromptContext {
                        selected_text: input
                            .selected_text
                            .as_deref()
                            .filter(|_| resolved.use_selected_text_context),
                        clipboard_text: input
                            .clipboard_text
                            .as_deref()
                            .filter(|_| resolved.use_clipboard_context),
                        window_context: window.as_deref(),
                        vocabulary: &config.vocabulary,
                    },
                };
                entry.enhancement_model = Some(format!(
                    "{} {}",
                    resolved.provider.display_name(),
                    resolved.model
                ));
                entry.prompt_name = Some(prompt.title.clone());
                match enhancement::enhance(&text, &request) {
                    Ok(result) => {
                        entry.enhancement_secs = Some(result.duration.as_secs_f64());
                        entry.enhanced_text = Some(result.text.clone());
                        final_text = result.text;
                    }
                    Err(e) => {
                        entry.enhancement_error = Some(e.to_string());
                        warning = Some(format!("Enhancement failed: {e}"));
                    }
                }
            } else {
                warning = Some(format!(
                    "Enhancement skipped: {} is not configured",
                    resolved.provider.display_name()
                ));
            }
        }
    }

    if cancel.load(Ordering::SeqCst) {
        return canceled(entry);
    }

    // 8. Snippet triggers inside a longer dictation are expanded after the
    // LLM ran, so it never rewrites the saved text.
    if snippet.is_none() && !config.snippets.is_empty() {
        let expanded = text::snippets::expand_inline(&final_text, &config.snippets, now);
        if expanded != final_text {
            entry.delivered_text = Some(expanded.clone());
            final_text = expanded;
        }
    }

    // A failed enhancement still delivers the cleaned transcript.
    let delivery = (!final_text.trim().is_empty()).then(|| Delivery {
        text: final_text,
        output: resolved.output,
        custom_command: resolved.custom_command.clone(),
        send_key: resolved.send_key,
    });

    PipelineOutput {
        entry,
        delivery,
        warning,
        error: None,
    }
}

/// Command Mode: sends the spoken instruction and the selected text to the
/// LLM and pastes the answer (replacing the selection, which is still
/// selected in the target app). Nothing is pasted when the request fails, so
/// the selection is never overwritten with the raw instruction.
fn run_command(
    config: &Config,
    input: &PipelineInput,
    mut entry: Entry,
    transcript: &str,
    cancel: &AtomicBool,
    on_stage: &dyn Fn(Stage),
) -> PipelineOutput {
    let fail = |mut entry: Entry, message: String| {
        entry.status = Status::Failed;
        entry.enhancement_error = Some(message.clone());
        PipelineOutput {
            entry,
            delivery: None,
            warning: None,
            error: Some(message),
        }
    };

    let instruction = text::apply_replacements(transcript, &config.replacements);
    entry.text = instruction.clone();
    entry.mode_name = Some("Command".into());
    if instruction.trim().is_empty() {
        return fail(entry, "No instruction was recognized.".into());
    }

    let (provider, model) = config.command.resolve(&config.enhancement);
    if !enhancement::is_configured(&config.enhancement, provider) {
        return fail(
            entry,
            format!(
                "Command Mode needs an AI provider: add a {} API key.",
                provider.display_name()
            ),
        );
    }
    if cancel.load(Ordering::SeqCst) {
        entry.status = Status::Canceled;
        return PipelineOutput {
            entry,
            delivery: None,
            warning: None,
            error: None,
        };
    }

    on_stage(Stage::Enhancing);
    let selected = input
        .selected_text
        .as_deref()
        .filter(|s| !s.trim().is_empty());
    let (system, user) =
        crate::prompts::build_command_messages(&instruction, selected, &config.vocabulary);
    entry.enhancement_model = Some(format!("{} {}", provider.display_name(), model));
    entry.prompt_name = Some(
        if selected.is_some() {
            "Command (edit selection)"
        } else {
            "Command (write)"
        }
        .into(),
    );

    match enhancement::complete_messages(
        &config.enhancement,
        provider,
        &model,
        "Command Mode",
        system,
        user,
    ) {
        Ok(result) => {
            entry.enhancement_secs = Some(result.duration.as_secs_f64());
            entry.delivered_text = Some(result.text.clone());
            if cancel.load(Ordering::SeqCst) {
                entry.status = Status::Canceled;
                return PipelineOutput {
                    entry,
                    delivery: None,
                    warning: None,
                    error: None,
                };
            }
            let delivery = (!result.text.trim().is_empty()).then_some(Delivery {
                text: result.text,
                output: OutputMode::Paste,
                custom_command: None,
                send_key: SendKey::None,
            });
            PipelineOutput {
                entry,
                delivery,
                warning: None,
                error: None,
            }
        }
        Err(e) => fail(entry, format!("Command failed: {e}")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::TranscriptionProvider;

    #[test]
    fn missing_key_reports_failure() {
        std::env::set_var(
            "VOICEINK_HOME",
            std::env::temp_dir().join("voiceink-pipeline-test"),
        );
        let mut cfg = Config::default();
        cfg.transcription.provider = TranscriptionProvider::Deepgram;
        cfg.history.enabled = false;
        std::env::remove_var("VOICEINK_DEEPGRAM_API_KEY");
        std::env::remove_var("DEEPGRAM_API_KEY");
        let input = PipelineInput {
            samples: vec![0.0; 16_000],
            ..Default::default()
        };
        let out = run(&cfg, &input, &AtomicBool::new(false), &|_| {});
        assert_eq!(out.entry.status, Status::Failed);
        assert!(out.error.unwrap().contains("Deepgram"));
        assert!(out.delivery.is_none());
        assert!((out.entry.duration - 1.0).abs() < 1e-9);
    }

    #[test]
    fn cancel_before_transcription() {
        let cfg = Config::default();
        let input = PipelineInput {
            samples: vec![0.0; 1600],
            ..Default::default()
        };
        let out = run(&cfg, &input, &AtomicBool::new(true), &|_| {
            panic!("no stage expected")
        });
        assert_eq!(out.entry.status, Status::Canceled);
    }

    /// Minimal HTTP/1.1 server answering each path with a canned (status, body).
    fn fake_server(
        routes: Vec<(&'static str, u16, &'static str)>,
    ) -> (String, std::thread::JoinHandle<Vec<String>>) {
        use std::io::{BufRead, BufReader, Read, Write};
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let handle = std::thread::spawn(move || {
            let mut seen = Vec::new();
            for _ in 0..routes.len() {
                let (mut stream, _) = listener.accept().unwrap();
                let mut reader = BufReader::new(stream.try_clone().unwrap());
                let mut request_line = String::new();
                reader.read_line(&mut request_line).unwrap();
                let mut len = 0usize;
                loop {
                    let mut line = String::new();
                    reader.read_line(&mut line).unwrap();
                    if line.trim().is_empty() {
                        break;
                    }
                    if let Some(v) = line.to_ascii_lowercase().strip_prefix("content-length:") {
                        len = v.trim().parse().unwrap();
                    }
                }
                let mut body = vec![0u8; len];
                reader.read_exact(&mut body).unwrap();
                let path = request_line.split_whitespace().nth(1).unwrap().to_string();
                let (_, status, reply) =
                    routes.iter().find(|(p, _, _)| *p == path).copied().unwrap();
                seen.push(format!("{path} {}", String::from_utf8_lossy(&body)));
                let resp = format!(
                    "HTTP/1.1 {status} X\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{reply}",
                    reply.len()
                );
                stream.write_all(resp.as_bytes()).unwrap();
            }
            seen
        });
        (base, handle)
    }

    fn local_config(base: &str) -> Config {
        let mut cfg = Config::default();
        cfg.history.enabled = false;
        cfg.transcription.provider = TranscriptionProvider::Custom;
        cfg.transcription.custom_endpoint = format!("{base}/v1/audio/transcriptions");
        cfg.enhancement.enabled = true;
        cfg.enhancement.provider = crate::config::EnhancementProvider::Custom;
        cfg.enhancement.custom_endpoint = format!("{base}/v1/chat/completions");
        cfg.enhancement.max_attempts = 1;
        cfg.replacements = vec![text::WordReplacement {
            original: "voice ink".into(),
            replacement: "VoiceInk".into(),
        }];
        cfg
    }

    #[test]
    fn end_to_end_with_enhancement() {
        let (base, server) = fake_server(vec![
            (
                "/v1/audio/transcriptions",
                200,
                r#"{"text":"Um, hello [MUSIC] voice ink."}"#,
            ),
            (
                "/v1/chat/completions",
                200,
                r#"{"choices":[{"message":{"content":"<think>x</think>Hello, VoiceInk!"}}]}"#,
            ),
        ]);
        let cfg = local_config(&base);
        let input = PipelineInput {
            samples: vec![0.0; 8000],
            ..Default::default()
        };
        let stages = std::sync::Mutex::new(Vec::new());
        let out = run(&cfg, &input, &AtomicBool::new(false), &|s| {
            stages.lock().unwrap().push(s)
        });

        assert!(out.error.is_none(), "{:?}", out.error);
        assert_eq!(out.entry.text, "hello VoiceInk.");
        assert_eq!(out.entry.enhanced_text.as_deref(), Some("Hello, VoiceInk!"));
        assert_eq!(out.delivery.unwrap().text, "Hello, VoiceInk!");
        assert_eq!(
            *stages.lock().unwrap(),
            vec![Stage::Transcribing, Stage::Enhancing]
        );

        let seen = server.join().unwrap();
        assert!(seen[0].contains("name=\"model\""));
        assert!(
            seen[1].contains("<TRANSCRIPT>\\nhello VoiceInk.\\n</TRANSCRIPT>"),
            "{}",
            seen[1]
        );
    }

    #[test]
    fn enhancement_failure_delivers_transcript() {
        let (base, server) = fake_server(vec![
            (
                "/v1/audio/transcriptions",
                200,
                r#"{"text":"plain words here"}"#,
            ),
            (
                "/v1/chat/completions",
                400,
                r#"{"error":{"message":"bad model"}}"#,
            ),
        ]);
        let cfg = local_config(&base);
        let input = PipelineInput {
            samples: vec![0.0; 8000],
            ..Default::default()
        };
        let out = run(&cfg, &input, &AtomicBool::new(false), &|_| {});
        server.join().unwrap();

        assert_eq!(out.entry.status, Status::Completed);
        assert_eq!(out.entry.enhanced_text, None);
        assert!(out
            .entry
            .enhancement_error
            .as_deref()
            .unwrap()
            .contains("bad model"));
        assert!(out.warning.unwrap().starts_with("Enhancement failed"));
        assert_eq!(out.delivery.unwrap().text, "plain words here");
        assert_eq!(out.entry.final_text(), "plain words here");
    }

    #[test]
    fn command_mode_edits_selection() {
        let (base, server) = fake_server(vec![
            (
                "/v1/audio/transcriptions",
                200,
                r#"{"text":"Make this more formal."}"#,
            ),
            (
                "/v1/chat/completions",
                200,
                r#"{"choices":[{"message":{"content":"Good afternoon, how are you?"}}]}"#,
            ),
        ]);
        let mut cfg = local_config(&base);
        cfg.enhancement.enabled = false; // Command Mode works regardless.
        let input = PipelineInput {
            samples: vec![0.0; 8000],
            selected_text: Some("hey whats up".into()),
            command: true,
            ..Default::default()
        };
        let out = run(&cfg, &input, &AtomicBool::new(false), &|_| {});
        let seen = server.join().unwrap();

        assert!(out.error.is_none(), "{:?}", out.error);
        assert_eq!(out.entry.mode_name.as_deref(), Some("Command"));
        assert_eq!(out.entry.text, "Make this more formal.");
        assert_eq!(out.entry.final_text(), "Good afternoon, how are you?");
        let d = out.delivery.unwrap();
        assert_eq!(d.text, "Good afternoon, how are you?");
        assert_eq!(d.output, OutputMode::Paste);
        assert!(
            seen[1].contains("<SELECTED_TEXT>\\nhey whats up\\n</SELECTED_TEXT>"),
            "{}",
            seen[1]
        );
        assert!(seen[1].contains("<INSTRUCTION>\\nMake this more formal.\\n</INSTRUCTION>"));
    }

    #[test]
    fn command_failure_pastes_nothing() {
        let (base, server) = fake_server(vec![
            (
                "/v1/audio/transcriptions",
                200,
                r#"{"text":"translate to German"}"#,
            ),
            (
                "/v1/chat/completions",
                500,
                r#"{"error":{"message":"overloaded"}}"#,
            ),
        ]);
        let cfg = local_config(&base);
        let input = PipelineInput {
            samples: vec![0.0; 8000],
            selected_text: Some("hello".into()),
            command: true,
            ..Default::default()
        };
        let out = run(&cfg, &input, &AtomicBool::new(false), &|_| {});
        server.join().unwrap();
        assert!(out.delivery.is_none());
        assert_eq!(out.entry.status, Status::Failed);
        assert!(out.error.unwrap().starts_with("Command failed"));
    }

    #[test]
    fn exact_snippet_skips_enhancement() {
        // Only the transcription request is served: enhancement must not run.
        let (base, server) = fake_server(vec![(
            "/v1/audio/transcriptions",
            200,
            r#"{"text":"My calendar link."}"#,
        )]);
        let mut cfg = local_config(&base);
        cfg.snippets = vec![text::Snippet {
            trigger: "my calendar link".into(),
            text: "https://cal.example.com/me".into(),
        }];
        let input = PipelineInput {
            samples: vec![0.0; 8000],
            ..Default::default()
        };
        let out = run(&cfg, &input, &AtomicBool::new(false), &|_| {});
        server.join().unwrap();
        assert_eq!(out.delivery.unwrap().text, "https://cal.example.com/me");
        assert_eq!(out.entry.enhanced_text, None);
        assert_eq!(out.entry.final_text(), "https://cal.example.com/me");
    }

    #[test]
    fn inline_snippet_expands_after_enhancement() {
        let (base, server) = fake_server(vec![
            (
                "/v1/audio/transcriptions",
                200,
                r#"{"text":"book via my calendar link"}"#,
            ),
            (
                "/v1/chat/completions",
                200,
                r#"{"choices":[{"message":{"content":"Book via my calendar link."}}]}"#,
            ),
        ]);
        let mut cfg = local_config(&base);
        cfg.snippets = vec![text::Snippet {
            trigger: "my calendar link".into(),
            text: "https://cal.example.com/me".into(),
        }];
        let input = PipelineInput {
            samples: vec![0.0; 8000],
            ..Default::default()
        };
        let out = run(&cfg, &input, &AtomicBool::new(false), &|_| {});
        server.join().unwrap();
        assert_eq!(
            out.entry.enhanced_text.as_deref(),
            Some("Book via my calendar link.")
        );
        assert_eq!(
            out.delivery.unwrap().text,
            "Book via https://cal.example.com/me."
        );
    }

    #[test]
    fn window_context_format() {
        let fg = ForegroundInfo {
            process_name: "code.exe".into(),
            window_title: "main.rs".into(),
        };
        assert_eq!(
            window_context(&fg).unwrap(),
            "Application: code.exe\nWindow title: main.rs"
        );
        assert!(window_context(&ForegroundInfo::default()).is_none());
    }
}
