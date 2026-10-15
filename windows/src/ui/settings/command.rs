//! Command Mode: spoken instructions applied to the selected text.

use super::super::style::{self, FIELD_WIDTH, Labeled, field, field_with_hint, indented};
use super::enhancement::providers;
use super::form::{self, KeyChanges};
use super::transcription::model_choices;
use crate::config::{Config, EnhancementProvider};
use crate::input::Hotkey;
use iced::widget::{checkbox, column, pick_list, row, text, text_input};
use iced::{Element, Length};

const SAME_AS_ENHANCEMENT: &str = "Same as AI Enhancement";

#[derive(Debug, Default)]
pub struct CommandMode {
    hotkey: String,
    model: String,
}

#[derive(Debug, Clone)]
pub enum Message {
    Enabled(bool),
    Hotkey(String),
    /// `None` uses the AI Enhancement provider.
    Provider(Labeled<Option<EnhancementProvider>>),
    Model(String),
}

fn provider_choices() -> Vec<Labeled<Option<EnhancementProvider>>> {
    std::iter::once(Labeled::new(None, SAME_AS_ENHANCEMENT))
        .chain(providers().into_iter().map(|p| Labeled::new(Some(p.value), p.label)))
        .collect()
}

impl CommandMode {
    pub fn new(config: &Config) -> Self {
        Self { hotkey: config.command.hotkey.clone(), model: config.command.model.clone().unwrap_or_default() }
    }

    pub fn update(&mut self, message: Message, config: &mut Config) {
        match message {
            Message::Enabled(on) => config.command.enabled = on,
            Message::Hotkey(v) => self.hotkey = v,
            Message::Provider(choice) => {
                config.command.provider = choice.value;
                self.model.clear();
            }
            Message::Model(v) => self.model = v,
        }
    }

    /// Runs after the General page, so the record shortcut is already updated.
    pub fn apply(&self, config: &mut Config, _keys: &mut KeyChanges) -> Result<(), String> {
        let hotkey = self.hotkey.trim().to_string();
        if config.command.enabled {
            let parsed = hotkey.parse::<Hotkey>().map_err(|e| format!("Command shortcut: {e}"))?;
            if config.hotkeys.record.parse::<Hotkey>().is_ok_and(|record| record == parsed) {
                return Err("The Command shortcut must differ from the record shortcut".into());
            }
        }
        config.command.hotkey = hotkey;
        config.command.model = form::optional(&self.model);
        Ok(())
    }

    pub fn view<'a>(&'a self, config: &'a Config) -> Element<'a, Message> {
        let choices = provider_choices();
        let current = choices.iter().copied().find(|c| c.value == config.command.provider);
        let models = config.command.provider.map(|p| model_choices(p.models(), p.default_model())).unwrap_or_default();
        column![
            text(
                "Select text in any app, press the Command shortcut and say what to do — \"make this more formal\", \
                 \"translate to German\", \"turn this into bullet points\". The result replaces the selection. With \
                 nothing selected, the instruction writes new text at the cursor."
            ),
            indented(checkbox(config.command.enabled).label("Enable Command Mode").on_toggle(Message::Enabled)),
            field_with_hint(
                "Command shortcut",
                text_input("Ctrl+Shift+Space", &self.hotkey).on_input(Message::Hotkey).width(200),
                "Uses the same tap / hold behaviour as the record shortcut",
            ),
            field("AI provider", pick_list(choices, current, Message::Provider).width(Length::Fixed(FIELD_WIDTH))),
            field_with_hint(
                "Model",
                row![
                    text_input("provider default", &self.model)
                        .on_input(Message::Model)
                        .width(Length::Fixed(FIELD_WIDTH)),
                    pick_list(models, None::<String>, Message::Model).placeholder("Choose…"),
                ]
                .spacing(8),
                "Leave empty for the provider's default. A capable model works best.",
            ),
        ]
        .spacing(style::SECTION_SPACING)
        .into()
    }
}
