//! Custom vocabulary and word replacements.

use super::super::style::{self, EDITOR_HEIGHT, hint};
use super::form;
use crate::config::Config;
use crate::text::{format_replacement_lines, parse_replacement_lines};
use iced::widget::{column, row, text, text_editor};
use iced::{Element, Fill};

#[derive(Debug, Default)]
pub struct Dictionary {
    vocabulary: text_editor::Content,
    replacements: text_editor::Content,
}

#[derive(Debug, Clone)]
pub enum Message {
    Vocabulary(text_editor::Action),
    Replacements(text_editor::Action),
}

impl Dictionary {
    pub fn new(config: &Config) -> Self {
        Self {
            vocabulary: text_editor::Content::with_text(&config.vocabulary.join("\n")),
            replacements: text_editor::Content::with_text(&format_replacement_lines(&config.replacements)),
        }
    }

    pub fn update(&mut self, message: Message) {
        match message {
            Message::Vocabulary(action) => self.vocabulary.perform(action),
            Message::Replacements(action) => self.replacements.perform(action),
        }
    }

    pub fn apply(&self, config: &mut Config) -> Result<(), String> {
        config.vocabulary = form::lines(&self.vocabulary.text());
        config.replacements =
            parse_replacement_lines(&self.replacements.text()).map_err(|e| format!("Replacements: {e}"))?;
        Ok(())
    }

    pub fn view(&self) -> Element<'_, Message> {
        column![
            row![
                column![
                    text("Vocabulary — one term per line"),
                    text_editor(&self.vocabulary).on_action(Message::Vocabulary).height(EDITOR_HEIGHT),
                ]
                .spacing(8)
                .width(Fill),
                column![
                    text("Replacements — one per line: spoken -> written"),
                    text_editor(&self.replacements).on_action(Message::Replacements).height(EDITOR_HEIGHT),
                ]
                .spacing(8)
                .width(Fill),
            ]
            .spacing(16),
            hint("Vocabulary guides spelling of names. Example replacement: voice ink, voice inc -> VoiceInk"),
        ]
        .spacing(style::SECTION_SPACING)
        .into()
    }
}
