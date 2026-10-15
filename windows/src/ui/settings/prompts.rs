//! Editor for the AI Enhancement prompts.

use super::super::style::{self, EDITOR_HEIGHT, FIELD_WIDTH, field, hint};
use super::enhancement::PromptChoice;
use super::form::Status;
use crate::config::Config;
use crate::prompts::CustomPrompt;
use iced::widget::{button, checkbox, column, pick_list, row, text, text_editor, text_input};
use iced::{Element, Length};

/// The prompt being edited and its instructions.
#[derive(Debug, Default)]
pub struct Prompts {
    /// Index into `config.prompts`.
    current: usize,
    instructions: text_editor::Content,
}

#[derive(Debug, Clone)]
pub enum Message {
    Select(PromptChoice),
    New,
    Delete,
    Title(String),
    SystemRules(bool),
    Instructions(text_editor::Action),
}

impl Prompts {
    pub fn new(config: &Config) -> Self {
        let current = config.prompts.iter().position(|p| p.id == config.enhancement.prompt_id).unwrap_or(0);
        let mut page = Self { current, instructions: text_editor::Content::new() };
        page.load(config);
        page
    }

    fn load(&mut self, config: &Config) {
        self.current = self.current.min(config.prompts.len().saturating_sub(1));
        let text = config.prompts.get(self.current).map_or("", |p| p.prompt_text.as_str());
        self.instructions = text_editor::Content::with_text(text);
    }

    pub fn update(&mut self, message: Message, config: &mut Config) -> Option<Status> {
        match message {
            Message::Select(choice) => {
                self.current = config.prompts.iter().position(|p| p.id == choice.id).unwrap_or(0);
                self.load(config);
            }
            Message::New => {
                config.prompts.push(CustomPrompt::new_user_prompt());
                self.current = config.prompts.len() - 1;
                self.load(config);
            }
            Message::Delete if config.prompts.len() <= 1 => {
                return Some(Status::error("At least one prompt is required."));
            }
            Message::Delete => {
                config.prompts.remove(self.current);
                self.load(config);
            }
            Message::Title(title) => {
                if let Some(prompt) = config.prompts.get_mut(self.current) {
                    prompt.title = title;
                }
            }
            Message::SystemRules(on) => {
                if let Some(prompt) = config.prompts.get_mut(self.current) {
                    prompt.use_system_instructions = on;
                }
            }
            Message::Instructions(action) => {
                let edited = action.is_edit();
                self.instructions.perform(action);
                if let Some(prompt) = config.prompts.get_mut(self.current).filter(|_| edited) {
                    prompt.prompt_text = self.instructions.text();
                }
            }
        }
        None
    }

    /// Prompts need a title.
    pub fn apply(config: &mut Config) -> Result<(), String> {
        for prompt in &mut config.prompts {
            prompt.title = prompt.title.trim().to_string();
            if prompt.title.is_empty() {
                return Err("Every prompt needs a title".into());
            }
        }
        Ok(())
    }

    pub fn view<'a>(&'a self, config: &'a Config) -> Element<'a, Message> {
        let Some(prompt) = config.prompts.get(self.current) else {
            return hint("No prompts. Click New to add one.");
        };
        let choices: Vec<PromptChoice> =
            config.prompts.iter().map(|p| PromptChoice { id: p.id.clone(), title: p.title.clone() }).collect();
        let current = PromptChoice { id: prompt.id.clone(), title: prompt.title.clone() };
        column![
            field(
                "Prompt",
                row![
                    pick_list(choices, Some(current), Message::Select).width(Length::Fixed(FIELD_WIDTH)),
                    button("New").on_press(Message::New).style(button::secondary),
                    button("Delete").on_press(Message::Delete).style(button::danger),
                ]
                .spacing(8),
            ),
            field(
                "Title",
                text_input("Title", &prompt.title).on_input(Message::Title).width(Length::Fixed(FIELD_WIDTH))
            ),
            checkbox(prompt.use_system_instructions)
                .label("Wrap with VoiceInk's transcription-cleaning rules (recommended)")
                .on_toggle(Message::SystemRules),
            text("Instructions"),
            text_editor(&self.instructions).on_action(Message::Instructions).height(EDITOR_HEIGHT),
        ]
        .spacing(style::SECTION_SPACING)
        .into()
    }
}
