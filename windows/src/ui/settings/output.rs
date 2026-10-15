//! How text is inserted into the focused app.

use super::super::style::{self, Labeled, field, field_with_hint, indented, selected};
use super::form;
use crate::config::{Config, PasteMethod, SendKey};
use iced::Element;
use iced::widget::{checkbox, column, pick_list, text_input};

const PASTE_METHODS: [Labeled<PasteMethod>; 3] = [
    Labeled::new(PasteMethod::CtrlV, "Clipboard + Ctrl+V (recommended)"),
    Labeled::new(PasteMethod::ShiftInsert, "Clipboard + Shift+Insert (terminals)"),
    Labeled::new(PasteMethod::Type, "Simulated typing (no clipboard)"),
];
const SEND_KEYS: [Labeled<SendKey>; 4] = [
    Labeled::new(SendKey::None, "Nothing"),
    Labeled::new(SendKey::Enter, "Enter"),
    Labeled::new(SendKey::ShiftEnter, "Shift+Enter"),
    Labeled::new(SendKey::CtrlEnter, "Ctrl+Enter"),
];

#[derive(Debug, Default)]
pub struct Output {
    restore_delay: String,
}

#[derive(Debug, Clone)]
pub enum Message {
    Method(Labeled<PasteMethod>),
    Restore(bool),
    RestoreDelay(String),
    SendKey(Labeled<SendKey>),
    AppendSpace(bool),
}

impl Output {
    pub fn new(config: &Config) -> Self {
        Self { restore_delay: config.output.clipboard_restore_delay_ms.to_string() }
    }

    pub fn update(&mut self, message: Message, config: &mut Config) {
        let output = &mut config.output;
        match message {
            Message::Method(method) => output.method = method.value,
            Message::Restore(on) => output.restore_clipboard = on,
            Message::RestoreDelay(v) => self.restore_delay = v,
            Message::SendKey(key) => output.send_key = key.value,
            Message::AppendSpace(on) => output.append_space = on,
        }
    }

    pub fn apply(&self, config: &mut Config) -> Result<(), String> {
        config.output.clipboard_restore_delay_ms = form::number(&self.restore_delay, "Restore delay")?;
        Ok(())
    }

    pub fn view<'a>(&'a self, config: &'a Config) -> Element<'a, Message> {
        let output = &config.output;
        column![
            field(
                "Insert text with",
                pick_list(PASTE_METHODS, selected(&PASTE_METHODS, output.method), Message::Method).width(320),
            ),
            indented(
                checkbox(output.restore_clipboard)
                    .label("Restore my clipboard after pasting")
                    .on_toggle(Message::Restore)
            ),
            field(
                "Restore after (ms)",
                text_input("600", &self.restore_delay).on_input(Message::RestoreDelay).width(100)
            ),
            field_with_hint(
                "Then press",
                pick_list(SEND_KEYS, selected(&SEND_KEYS, output.send_key), Message::SendKey).width(200),
                "\"Finish & Send\": submit chat messages automatically",
            ),
            indented(
                checkbox(output.append_space)
                    .label("Add a trailing space after each dictation")
                    .on_toggle(Message::AppendSpace)
            ),
        ]
        .spacing(style::SECTION_SPACING)
        .into()
    }
}
