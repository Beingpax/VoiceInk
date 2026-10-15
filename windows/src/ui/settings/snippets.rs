//! Voice shortcuts that expand to saved text.

use super::super::style::{self, EDITOR_HEIGHT, hint};
use crate::config::Config;
use crate::text::snippets;
use iced::Element;
use iced::widget::{column, text, text_editor};

#[derive(Debug, Default)]
pub struct Snippets {
    lines: text_editor::Content,
}

#[derive(Debug, Clone)]
pub enum Message {
    Edit(text_editor::Action),
}

impl Snippets {
    pub fn new(config: &Config) -> Self {
        Self { lines: text_editor::Content::with_text(&snippets::format_lines(&config.snippets)) }
    }

    pub fn update(&mut self, Message::Edit(action): Message) {
        self.lines.perform(action);
    }

    pub fn apply(&self, config: &mut Config) -> Result<(), String> {
        config.snippets = snippets::parse_lines(&self.lines.text()).map_err(|e| format!("Snippets: {e}"))?;
        Ok(())
    }

    pub fn view(&self) -> Element<'_, Message> {
        column![
            text(
                "Say a trigger phrase and VoiceInk types the saved text. Saying only the trigger inserts the \
                 snippet as-is; inside a longer dictation it is expanded after AI clean-up."
            ),
            hint("One per line:  trigger => text    (\\n = line break, {date} {time} {datetime})"),
            text_editor(&self.lines).on_action(Message::Edit).height(EDITOR_HEIGHT),
            hint("Example:  my calendar link => https://cal.com/yourname"),
        ]
        .spacing(style::SECTION_SPACING)
        .into()
    }
}
