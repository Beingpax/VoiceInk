//! AI clean-up of transcripts: provider, model, prompt and context.

use super::super::style::{self, FIELD_WIDTH, Labeled, field, indented};
use super::form::{self, Env, KeyChanges, KeyField, KeyMessage, Status};
use super::transcription::model_choices;
use crate::config::{Config, EnhancementProvider};
use iced::widget::{checkbox, column, pick_list, row, text, text_input};
use iced::{Element, Length};

const TIMEOUT_RANGE_SECS: (u64, u64) = (5, 600);

#[derive(Debug, Default)]
pub struct Enhancement {
    model: String,
    key: KeyField,
    short_words: String,
    timeout: String,
}

#[derive(Debug, Clone)]
pub enum Message {
    Enabled(bool),
    Provider(Labeled<EnhancementProvider>),
    Model(String),
    Prompt(PromptChoice),
    Key(KeyMessage),
    Endpoint(String),
    WindowContext(bool),
    ClipboardContext(bool),
    SelectionContext(bool),
    SkipShort(bool),
    ShortWords(String),
    Timeout(String),
}

/// A prompt in the pick list, identified by its id.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PromptChoice {
    pub id: String,
    pub title: String,
}

impl std::fmt::Display for PromptChoice {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.title)
    }
}

pub fn providers() -> Vec<Labeled<EnhancementProvider>> {
    EnhancementProvider::ALL.iter().map(|&p| Labeled::new(p, p.display_name())).collect()
}

/// Ollama and the custom provider need an endpoint.
fn endpoint_caption(provider: EnhancementProvider) -> Option<&'static str> {
    match provider {
        EnhancementProvider::Ollama => Some("Ollama URL"),
        EnhancementProvider::Custom => Some("Chat endpoint"),
        _ => None,
    }
}

impl Enhancement {
    pub fn new(config: &Config, env: Env<'_>) -> Self {
        let settings = &config.enhancement;
        let mut page = Self {
            model: settings.model_name(),
            key: KeyField::default(),
            short_words: settings.short_transcript_word_threshold.to_string(),
            timeout: settings.timeout_secs.to_string(),
        };
        page.key.refresh(settings.provider.credential_key(), env);
        page
    }

    pub fn update(&mut self, message: Message, config: &mut Config, env: Env<'_>) -> Option<Status> {
        let settings = &mut config.enhancement;
        match message {
            Message::Enabled(on) => settings.enabled = on,
            Message::Provider(p) => {
                settings.set_provider(p.value);
                self.model = p.value.default_model().to_string();
                self.key.refresh(p.value.credential_key(), env);
            }
            Message::Model(model) => self.model = model,
            Message::Prompt(choice) => settings.prompt_id = choice.id,
            Message::Key(message) => return self.key.update(message, settings.provider.credential_key(), env),
            Message::Endpoint(url) => match settings.provider {
                EnhancementProvider::Ollama => settings.ollama_base_url = url,
                EnhancementProvider::Custom => settings.custom_endpoint = url,
                _ => {}
            },
            Message::WindowContext(on) => settings.use_window_context = on,
            Message::ClipboardContext(on) => settings.use_clipboard_context = on,
            Message::SelectionContext(on) => settings.use_selected_text_context = on,
            Message::SkipShort(on) => settings.skip_short_transcripts = on,
            Message::ShortWords(v) => self.short_words = v,
            Message::Timeout(v) => self.timeout = v,
        }
        None
    }

    pub fn apply(&self, config: &mut Config, keys: &mut KeyChanges) -> Result<(), String> {
        let settings = &mut config.enhancement;
        settings.model = form::model_override(&self.model, settings.provider.default_model());
        settings.short_transcript_word_threshold = form::count(&self.short_words, "Short dictation words")?;
        settings.timeout_secs =
            form::number(&self.timeout, "Timeout")?.clamp(TIMEOUT_RANGE_SECS.0, TIMEOUT_RANGE_SECS.1);
        settings.ollama_base_url = settings.ollama_base_url.trim().to_string();
        settings.custom_endpoint = settings.custom_endpoint.trim().to_string();
        self.key.collect(config.enhancement.provider.credential_key(), keys);
        Ok(())
    }

    pub fn saved(&mut self, config: &Config, env: Env<'_>) {
        self.key.saved(config.enhancement.provider.credential_key(), env);
    }

    pub fn view<'a>(&'a self, config: &'a Config) -> Element<'a, Message> {
        let settings = &config.enhancement;
        let provider = settings.provider;
        let prompts: Vec<PromptChoice> =
            config.prompts.iter().map(|p| PromptChoice { id: p.id.clone(), title: p.title.clone() }).collect();
        let prompt = config.active_prompt(None).map(|p| PromptChoice { id: p.id.clone(), title: p.title.clone() });
        let mut page = column![
            indented(checkbox(settings.enabled).label("Clean up transcripts with AI").on_toggle(Message::Enabled)),
            field(
                "Provider",
                pick_list(providers(), Some(Labeled::new(provider, provider.display_name())), Message::Provider)
                    .width(Length::Fixed(FIELD_WIDTH)),
            ),
            field(
                "Model",
                row![
                    text_input(provider.default_model(), &self.model)
                        .on_input(Message::Model)
                        .width(Length::Fixed(FIELD_WIDTH)),
                    pick_list(
                        model_choices(provider.models(), provider.default_model()),
                        None::<String>,
                        Message::Model
                    )
                    .placeholder("Choose…"),
                ]
                .spacing(8),
            ),
            field("Prompt", pick_list(prompts, prompt, Message::Prompt).width(Length::Fixed(FIELD_WIDTH))),
            field("API key", self.key.view().map(Message::Key)),
        ]
        .spacing(style::SECTION_SPACING);
        if let Some(caption) = endpoint_caption(provider) {
            let url = if provider == EnhancementProvider::Ollama {
                &settings.ollama_base_url
            } else {
                &settings.custom_endpoint
            };
            page = page.push(field(caption, text_input("http://…", url).on_input(Message::Endpoint)));
        }
        page.push(field(
            "Context",
            column![
                checkbox(settings.use_window_context)
                    .label("Active window title and app")
                    .on_toggle(Message::WindowContext),
                checkbox(settings.use_clipboard_context).label("Clipboard text").on_toggle(Message::ClipboardContext),
                checkbox(settings.use_selected_text_context)
                    .label("Selected text (copied when recording starts)")
                    .on_toggle(Message::SelectionContext),
            ]
            .spacing(8),
        ))
        .push(indented(
            row![
                checkbox(settings.skip_short_transcripts)
                    .label("Skip AI for short dictations of at most")
                    .on_toggle(Message::SkipShort),
                text_input("3", &self.short_words).on_input(Message::ShortWords).width(50),
                text("words"),
            ]
            .spacing(8)
            .align_y(iced::Center),
        ))
        .push(field("Timeout (seconds)", text_input("30", &self.timeout).on_input(Message::Timeout).width(80)))
        .into()
    }
}
