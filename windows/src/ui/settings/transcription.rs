//! Speech-to-text provider, model, language and output clean-up.

use super::super::style::{self, FIELD_WIDTH, Labeled, field, field_with_hint, indented};
use super::form::{self, Env, KeyChanges, KeyField, KeyMessage, Status};
use crate::config::{Config, LANGUAGES, TranscriptionProvider};
use iced::widget::{checkbox, column, pick_list, row, text_input};
use iced::{Element, Length};

#[derive(Debug, Default)]
pub struct Transcription {
    model: String,
    key: KeyField,
    fillers: String,
}

#[derive(Debug, Clone)]
pub enum Message {
    Provider(Labeled<TranscriptionProvider>),
    Model(String),
    Language(Labeled<&'static str>),
    Key(KeyMessage),
    Endpoint(String),
    Filter(bool),
    Formatting(bool),
    Fillers(String),
}

fn providers() -> Vec<Labeled<TranscriptionProvider>> {
    TranscriptionProvider::ALL.iter().map(|&p| Labeled::new(p, p.display_name())).collect()
}

/// Known models, offered as suggestions next to the free-text field.
pub fn model_choices(models: &[&'static str], default: &'static str) -> Vec<String> {
    let models = if models.is_empty() && !default.is_empty() { &[default][..] } else { models };
    models.iter().map(ToString::to_string).collect()
}

impl Transcription {
    pub fn new(config: &Config, env: Env<'_>) -> Self {
        let settings = &config.transcription;
        let mut page =
            Self { model: settings.model_name(), key: KeyField::default(), fillers: config.filler_words.join(", ") };
        page.key.refresh(settings.provider.credential_key(), env);
        page
    }

    pub fn update(&mut self, message: Message, config: &mut Config, env: Env<'_>) -> Option<Status> {
        let settings = &mut config.transcription;
        match message {
            Message::Provider(p) => {
                settings.set_provider(p.value);
                self.model = p.value.default_model().to_string();
                self.key.refresh(p.value.credential_key(), env);
            }
            Message::Model(model) => self.model = model,
            Message::Language(language) => settings.language = language.value.to_string(),
            Message::Key(message) => return self.key.update(message, settings.provider.credential_key(), env),
            Message::Endpoint(url) => settings.custom_endpoint = url,
            Message::Filter(on) => settings.filter_output = on,
            Message::Formatting(on) => settings.text_formatting = on,
            Message::Fillers(words) => self.fillers = words,
        }
        None
    }

    pub fn apply(&self, config: &mut Config, keys: &mut KeyChanges) {
        let settings = &mut config.transcription;
        settings.model = form::model_override(&self.model, settings.provider.default_model());
        settings.custom_endpoint = settings.custom_endpoint.trim().to_string();
        config.filler_words =
            self.fillers.split(',').map(|w| w.trim().to_lowercase()).filter(|w| !w.is_empty()).collect();
        self.key.collect(config.transcription.provider.credential_key(), keys);
    }

    pub fn saved(&mut self, config: &Config, env: Env<'_>) {
        self.key.saved(config.transcription.provider.credential_key(), env);
    }

    pub fn view<'a>(&'a self, config: &'a Config) -> Element<'a, Message> {
        let settings = &config.transcription;
        let provider = settings.provider;
        let languages: Vec<Labeled<&'static str>> =
            LANGUAGES.iter().map(|&(code, name)| Labeled::new(code, name)).collect();
        let language = languages.iter().copied().find(|l| l.value.eq_ignore_ascii_case(&settings.language));
        column![
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
            field("Language", pick_list(languages, language, Message::Language).width(Length::Fixed(FIELD_WIDTH))),
            field("API key", self.key.view().map(Message::Key)),
            field_with_hint(
                "Custom endpoint",
                text_input("https://…/v1/audio/transcriptions", &settings.custom_endpoint).on_input(Message::Endpoint),
                "Used by the Custom provider, e.g. a local whisper.cpp server",
            ),
            indented(
                checkbox(settings.filter_output)
                    .label("Remove filler words and noise tags like [MUSIC]")
                    .on_toggle(Message::Filter)
            ),
            indented(
                checkbox(settings.text_formatting)
                    .label("Format long dictations into paragraphs")
                    .on_toggle(Message::Formatting)
            ),
            field_with_hint(
                "Filler words",
                text_input("um, uh", &self.fillers).on_input(Message::Fillers),
                "Comma separated"
            ),
        ]
        .spacing(style::SECTION_SPACING)
        .into()
    }
}
