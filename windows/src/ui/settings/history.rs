//! History retention, export and deletion.

use super::super::style::{self, field_with_hint, indented};
use super::dashboard::export_history;
use super::form::{self, Env, Status};
use crate::config::Config;
use iced::Element;
use iced::widget::{button, checkbox, column, row, text, text_input};

#[derive(Debug, Default)]
pub struct History {
    max_entries: String,
    /// "Delete all history" was clicked once and waits for confirmation.
    confirming_clear: bool,
}

#[derive(Debug, Clone)]
pub enum Message {
    Enabled(bool),
    SaveAudio(bool),
    MaxEntries(String),
    Export,
    OpenFolder,
    Clear,
    ConfirmClear,
    CancelClear,
}

impl History {
    pub fn new(config: &Config) -> Self {
        Self { max_entries: config.history.max_entries.to_string(), confirming_clear: false }
    }

    pub fn update(&mut self, message: Message, config: &mut Config, env: Env<'_>) -> Option<Status> {
        match message {
            Message::Enabled(on) => config.history.enabled = on,
            Message::SaveAudio(on) => config.history.save_audio = on,
            Message::MaxEntries(v) => self.max_entries = v,
            Message::Export => return Some(export_history(env)),
            Message::OpenFolder => env.desktop.open_path(env.app.paths.root()),
            Message::Clear => self.confirming_clear = true,
            Message::CancelClear => self.confirming_clear = false,
            Message::ConfirmClear => {
                self.confirming_clear = false;
                return Some(match env.app.history.clear() {
                    Ok(()) => Status::info("History deleted"),
                    Err(e) => Status::error(format!("Could not delete the history: {e}")),
                });
            }
        }
        None
    }

    pub fn apply(&self, config: &mut Config) -> Result<(), String> {
        config.history.max_entries = form::count(&self.max_entries, "History size")?;
        Ok(())
    }

    pub fn view<'a>(&'a self, config: &'a Config) -> Element<'a, Message> {
        let clear: Element<'a, Message> = if self.confirming_clear {
            row![
                text("Delete all transcriptions and saved recordings? This cannot be undone."),
                button("Delete everything").on_press(Message::ConfirmClear).style(button::danger),
                button("Cancel").on_press(Message::CancelClear).style(button::secondary),
            ]
            .spacing(8)
            .align_y(iced::Center)
            .into()
        } else {
            row![
                button("Export CSV").on_press(Message::Export).style(button::secondary),
                button("Open data folder").on_press(Message::OpenFolder).style(button::secondary),
                button("Delete all history").on_press(Message::Clear).style(button::danger),
            ]
            .spacing(8)
            .into()
        };
        column![
            indented(
                checkbox(config.history.enabled).label("Keep a history of transcriptions").on_toggle(Message::Enabled)
            ),
            indented(
                checkbox(config.history.save_audio)
                    .label("Also keep the audio recordings")
                    .on_toggle(Message::SaveAudio)
            ),
            field_with_hint(
                "Keep at most (entries)",
                text_input("1000", &self.max_entries).on_input(Message::MaxEntries).width(100),
                "0 keeps everything",
            ),
            indented(clear),
        ]
        .spacing(style::SECTION_SPACING)
        .into()
    }
}
