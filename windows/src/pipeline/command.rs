//! The Command Mode flow: the transcript is an instruction applied to the
//! selected text (or used to write new text) by the LLM.

use super::{Delivery, Finished, Pipeline, PipelineInput, Stage, Stop};
use crate::history::Entry;
use crate::modes;
use crate::prompts::build_command_messages;
use crate::text;
use std::time::Instant;

const MODE_NAME: &str = "Command";

impl Pipeline<'_> {
    /// Nothing is pasted when the request fails, so the selection (still
    /// selected in the target app) is never overwritten with the instruction.
    pub(super) fn run_command(&self, input: &PipelineInput, entry: &mut Entry) -> Result<Finished, Stop> {
        let config = self.config;
        let fail = |entry: &mut Entry, message: String| {
            entry.enhancement_error = Some(message.clone());
            Stop::Failed(message)
        };

        // A matching mode may set the language (e.g. German for an email app).
        let language = modes::resolve(config, modes::match_mode(&config.modes, &input.foreground)).language;
        let transcript = self.transcribe(input, language.as_deref(), entry)?;
        let instruction = text::apply_replacements(&transcript, &config.replacements);
        entry.text.clone_from(&instruction);
        entry.mode_name = Some(MODE_NAME.into());
        if instruction.trim().is_empty() {
            return Err(fail(entry, "No instruction was recognized.".into()));
        }

        let (provider, model_name) = config.command.resolve(&config.enhancement);
        let model = self.services.chat_model(&config.enhancement, provider, &model_name).map_err(|_| {
            fail(entry, format!("Command Mode needs an AI provider: add a {} API key.", provider.display_name()))
        })?;
        self.check_cancel()?;
        (self.on_stage)(Stage::Enhancing);

        let selected = input.selected_text.as_deref().filter(|s| !s.trim().is_empty());
        let (system, user) = build_command_messages(&instruction, selected, &config.vocabulary);
        entry.enhancement_model = Some(format!("{} {model_name}", provider.display_name()));
        entry.prompt_name =
            Some(if selected.is_some() { "Command (edit selection)" } else { "Command (write)" }.into());

        let started = Instant::now();
        let answer = model.complete(&system, &user);
        entry.enhancement_secs = Some(started.elapsed().as_secs_f64());
        let result = text::filter_enhancement_output(&answer.map_err(|e| fail(entry, format!("Command failed: {e}")))?);
        entry.delivered_text = Some(result.clone());
        self.check_cancel()?;

        let delivery = (!result.trim().is_empty()).then(|| Delivery::paste(result));
        Ok(Finished { delivery, warning: None })
    }
}
