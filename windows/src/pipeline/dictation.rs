//! The dictation flow.

use super::{Delivery, Finished, Pipeline, PipelineInput, Stage, Stop};
use crate::enhancement::EnhancementError;
use crate::history::Entry;
use crate::modes::{self, ForegroundInfo, Resolved};
use crate::prompts::{PromptContext, build_system_message, build_user_message};
use crate::text::{self, snippets};
use chrono::{DateTime, Local};
use std::time::Instant;

/// Result of the optional AI step.
struct Enhanced {
    text: String,
    warning: Option<String>,
}

impl Pipeline<'_> {
    pub(super) fn run_dictation(&self, input: &PipelineInput, entry: &mut Entry) -> Result<Finished, Stop> {
        let config = self.config;
        let mut resolved = modes::resolve(config, modes::match_mode(&config.modes, &input.foreground));
        let mut text = self.transcribe(input, resolved.language.as_deref(), entry)?;

        // Spoken trigger words switch the mode.
        if let Some(detection) = modes::detect_trigger(&text, &config.modes) {
            resolved = modes::resolve(config, config.modes.get(detection.mode_index));
            text = detection.processed_text;
        }
        if resolved.text_formatting {
            text = text::format_paragraphs(&text);
        }
        text = text::apply_replacements(&text, &config.replacements);
        entry.text.clone_from(&text);
        entry.mode_name.clone_from(&resolved.mode_name);

        let now = self.services.now();
        // Saying only a snippet's trigger inserts the snippet verbatim, without AI.
        if let Some(snippet) = snippets::exact_match(&text, &config.snippets) {
            let rendered = snippets::render(&snippet.text, now);
            entry.delivered_text = Some(rendered.clone());
            return Ok(Finished { delivery: Some(deliver(rendered, &resolved)), warning: None });
        }

        let Enhanced { text: mut final_text, warning } = self.enhance(input, &text, &resolved, entry)?;
        self.check_cancel()?;

        // Triggers inside a longer dictation expand after the LLM ran, so it
        // never rewrites the saved text.
        let expanded = expand(&final_text, &config.snippets, now);
        if expanded != final_text {
            entry.delivered_text = Some(expanded.clone());
            final_text = expanded;
        }

        // A failed enhancement still delivers the cleaned transcript.
        let delivery = (!final_text.trim().is_empty()).then(|| deliver(final_text, &resolved));
        Ok(Finished { delivery, warning })
    }

    /// Runs AI enhancement when enabled; falls back to `text` on failure.
    fn enhance(
        &self,
        input: &PipelineInput,
        text: &str,
        resolved: &Resolved,
        entry: &mut Entry,
    ) -> Result<Enhanced, Stop> {
        let unchanged = |warning| Ok(Enhanced { text: text.to_string(), warning });
        let config = self.config;
        let too_short = config.enhancement.skip_short_transcripts
            && text::word_count(text) <= config.enhancement.short_transcript_word_threshold.max(1);
        let Some(prompt) = config.active_prompt(Some(&resolved.prompt_id)) else {
            return unchanged(None);
        };
        if !resolved.enhancement_enabled || too_short || text.is_empty() {
            return unchanged(None);
        }

        let model = match self.services.chat_model(&config.enhancement, resolved.provider, &resolved.model) {
            Ok(model) => model,
            Err(EnhancementError::NotConfigured(_)) => {
                return unchanged(Some(format!(
                    "Enhancement skipped: {} is not configured",
                    resolved.provider.display_name()
                )));
            }
            Err(e) => return unchanged(Some(format!("Enhancement failed: {e}"))),
        };
        self.check_cancel()?;
        (self.on_stage)(Stage::Enhancing);

        let window = resolved.use_window_context.then(|| window_context(&input.foreground)).flatten();
        let context = PromptContext {
            selected_text: input.selected_text.as_deref().filter(|_| resolved.use_selected_text_context),
            clipboard_text: input.clipboard_text.as_deref().filter(|_| resolved.use_clipboard_context),
            window_context: window.as_deref(),
            vocabulary: &config.vocabulary,
        };
        entry.enhancement_model = Some(format!("{} {}", resolved.provider.display_name(), resolved.model));
        entry.prompt_name = Some(prompt.title.clone());

        let started = Instant::now();
        let answer = model
            .complete(&build_system_message(prompt, &context), &build_user_message(text))
            .map(|raw| text::filter_enhancement_output(&raw))
            .and_then(|clean| if clean.is_empty() { Err(EnhancementError::EmptyResponse) } else { Ok(clean) });
        entry.enhancement_secs = Some(started.elapsed().as_secs_f64());

        match answer {
            Ok(enhanced) => {
                entry.enhanced_text = Some(enhanced.clone());
                Ok(Enhanced { text: enhanced, warning: None })
            }
            Err(e) => {
                entry.enhancement_error = Some(e.to_string());
                unchanged(Some(format!("Enhancement failed: {e}")))
            }
        }
    }
}

fn deliver(text: String, resolved: &Resolved) -> Delivery {
    Delivery {
        text,
        output: resolved.output,
        custom_command: resolved.custom_command.clone(),
        send_key: resolved.send_key,
    }
}

fn expand(text: &str, list: &[text::Snippet], now: DateTime<Local>) -> String {
    if list.is_empty() { text.to_string() } else { snippets::expand_inline(text, list, now) }
}

/// "Application: …\nWindow title: …" for the AI context.
pub(super) fn window_context(fg: &ForegroundInfo) -> Option<String> {
    let mut lines = Vec::new();
    if !fg.process_name.is_empty() {
        lines.push(format!("Application: {}", fg.process_name));
    }
    if !fg.window_title.trim().is_empty() {
        lines.push(format!("Window title: {}", fg.window_title.trim()));
    }
    (!lines.is_empty()).then(|| lines.join("\n"))
}
