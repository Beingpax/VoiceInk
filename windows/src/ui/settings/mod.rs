//! The Dashboard & Settings window.
//!
//! The window edits a working copy of the [`Config`]. Toggles and choices
//! write to it directly; free-text fields (shortcuts, numbers, word lists)
//! are kept by their page and validated in its `apply` step when the user
//! clicks **Save**, which then writes `config.json` and the typed API keys.

mod command;
mod dashboard;
mod dictionary;
mod enhancement;
mod form;
mod general;
mod history;
mod output;
mod prompts;
mod snippets;
#[cfg(test)]
mod tests;
mod transcription;

use super::Desktop;
use super::style::{self, NAV_WIDTH, PAGE_PADDING};
use crate::config::{Config, ConfigError};
use crate::context::AppContext;
use crate::settings_page::SettingsPage;
use form::{Env, KeyChanges, Status};
use iced::widget::{Column, button, column, container, row, scrollable, space, text};
use iced::{Element, Fill, Length};
use std::rc::Rc;

#[derive(Debug, Clone)]
pub enum Message {
    Navigate(SettingsPage),
    Save,
    Close,
    Dashboard(dashboard::Message),
    General(general::Message),
    Transcription(transcription::Message),
    Enhancement(enhancement::Message),
    Prompts(prompts::Message),
    Dictionary(dictionary::Message),
    Snippets(snippets::Message),
    Command(command::Message),
    Output(output::Message),
    History(history::Message),
}

/// What the surrounding daemon has to do after an update.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Outcome {
    None,
    /// Settings and keys were written; the app should reload them.
    Saved,
    Close,
}

pub struct SettingsWindow {
    ctx: AppContext,
    desktop: Rc<dyn Desktop>,
    page: SettingsPage,
    /// The configuration as edited so far.
    config: Config,
    status: Option<Status>,
    dashboard: dashboard::Dashboard,
    general: general::General,
    transcription: transcription::Transcription,
    enhancement: enhancement::Enhancement,
    prompts: prompts::Prompts,
    dictionary: dictionary::Dictionary,
    snippets: snippets::Snippets,
    command: command::CommandMode,
    output: output::Output,
    history: history::History,
}

impl SettingsWindow {
    /// Loads the settings file and opens on `page`.
    ///
    /// # Errors
    /// Returns [`ConfigError`] when the settings file is invalid.
    pub fn new(ctx: AppContext, desktop: Rc<dyn Desktop>, page: SettingsPage) -> Result<Self, ConfigError> {
        let config = ctx.load_config()?;
        let env = Env { app: &ctx, desktop: desktop.as_ref() };
        let mut window = Self {
            general: general::General::new(&config, env),
            transcription: transcription::Transcription::new(&config, env),
            enhancement: enhancement::Enhancement::new(&config, env),
            prompts: prompts::Prompts::new(&config),
            dictionary: dictionary::Dictionary::new(&config),
            snippets: snippets::Snippets::new(&config),
            command: command::CommandMode::new(&config),
            output: output::Output::new(&config),
            history: history::History::new(&config),
            dashboard: dashboard::Dashboard::default(),
            status: None,
            page,
            config,
            ctx,
            desktop,
        };
        window.show_page(page);
        Ok(window)
    }

    pub fn title() -> &'static str {
        "VoiceInk — Dashboard & Settings"
    }

    pub fn show_page(&mut self, page: SettingsPage) {
        self.page = page;
        self.status = None;
        if page == SettingsPage::Dashboard {
            self.dashboard.refresh(Env { app: &self.ctx, desktop: self.desktop.as_ref() });
        }
    }

    /// A dictation finished: refresh the dashboard if it is showing.
    pub fn history_changed(&mut self) {
        if self.page == SettingsPage::Dashboard {
            self.dashboard.refresh(Env { app: &self.ctx, desktop: self.desktop.as_ref() });
        }
    }

    pub fn update(&mut self, message: Message) -> Outcome {
        let env = Env { app: &self.ctx, desktop: self.desktop.as_ref() };
        let config = &mut self.config;
        let status = match message {
            Message::Navigate(page) => {
                self.show_page(page);
                return Outcome::None;
            }
            Message::Save => return self.save(),
            Message::Close => return Outcome::Close,
            Message::Dashboard(m) => self.dashboard.update(m, env),
            Message::General(m) => self.general.update(m, config, env),
            Message::Transcription(m) => self.transcription.update(m, config, env),
            Message::Enhancement(m) => self.enhancement.update(m, config, env),
            Message::Prompts(m) => self.prompts.update(m, config),
            Message::Dictionary(m) => {
                self.dictionary.update(m);
                None
            }
            Message::Snippets(m) => {
                self.snippets.update(m);
                None
            }
            Message::Command(m) => {
                self.command.update(m, config);
                None
            }
            Message::Output(m) => {
                self.output.update(m, config);
                None
            }
            Message::History(m) => self.history.update(m, config, env),
        };
        if status.is_some() {
            self.status = status;
        }
        Outcome::None
    }

    /// Lets every page validate and apply its fields to a copy of the
    /// working configuration, in navigation order.
    fn collect(&self) -> Result<(Config, KeyChanges), (SettingsPage, String)> {
        let mut config = self.config.clone();
        let mut keys = KeyChanges::new();
        let at = |page: SettingsPage| move |message: String| (page, message);
        self.general.apply(&mut config, &mut keys).map_err(at(SettingsPage::General))?;
        self.transcription.apply(&mut config, &mut keys);
        self.enhancement.apply(&mut config, &mut keys).map_err(at(SettingsPage::Enhancement))?;
        prompts::Prompts::apply(&mut config).map_err(at(SettingsPage::Prompts))?;
        self.dictionary.apply(&mut config).map_err(at(SettingsPage::Dictionary))?;
        self.snippets.apply(&mut config).map_err(at(SettingsPage::Snippets))?;
        self.command.apply(&mut config, &mut keys).map_err(at(SettingsPage::CommandMode))?;
        self.output.apply(&mut config).map_err(at(SettingsPage::Output))?;
        self.history.apply(&mut config).map_err(at(SettingsPage::History))?;
        // Modes have no page; keep hand edits made while the window was open.
        if let Ok(disk) = self.ctx.load_config() {
            config.modes = disk.modes;
        }
        Ok((config, keys))
    }

    fn save(&mut self) -> Outcome {
        let (config, keys) = match self.collect() {
            Ok(collected) => collected,
            Err((page, message)) => {
                self.page = page;
                self.status = Some(Status::error(message));
                return Outcome::None;
            }
        };
        if let Err(e) = config.save(&self.ctx.paths.config()) {
            self.status = Some(Status::error(format!("Could not save settings: {e}")));
            return Outcome::None;
        }
        let failed: Vec<String> = keys
            .iter()
            .filter_map(|(name, key)| self.ctx.secrets.set(name, key).err().map(|e| format!("{name}: {e}")))
            .collect();
        self.config = config;
        let env = Env { app: &self.ctx, desktop: self.desktop.as_ref() };
        self.transcription.saved(&self.config, env);
        self.enhancement.saved(&self.config, env);
        self.status = Some(if failed.is_empty() {
            Status::info("Settings saved.")
        } else {
            Status::error(format!("Some API keys were not saved: {}", failed.join("; ")))
        });
        Outcome::Saved
    }

    pub fn view(&self) -> Element<'_, Message> {
        let content = self.page_view();
        let body = column![
            style::title(self.page.title()),
            scrollable(container(content).padding([0, 8])).height(Fill),
            self.footer(),
        ]
        .spacing(16)
        .padding(PAGE_PADDING);
        row![self.navigation(), body].into()
    }

    fn page_view(&self) -> Element<'_, Message> {
        let config = &self.config;
        match self.page {
            SettingsPage::Dashboard => self.dashboard.view().map(Message::Dashboard),
            SettingsPage::General => self.general.view(config).map(Message::General),
            SettingsPage::Transcription => self.transcription.view(config).map(Message::Transcription),
            SettingsPage::Enhancement => self.enhancement.view(config).map(Message::Enhancement),
            SettingsPage::Prompts => self.prompts.view(config).map(Message::Prompts),
            SettingsPage::Dictionary => self.dictionary.view().map(Message::Dictionary),
            SettingsPage::Snippets => self.snippets.view().map(Message::Snippets),
            SettingsPage::CommandMode => self.command.view(config).map(Message::Command),
            SettingsPage::Output => self.output.view(config).map(Message::Output),
            SettingsPage::History => self.history.view(config).map(Message::History),
        }
    }

    fn navigation(&self) -> Element<'_, Message> {
        let items = SettingsPage::ALL.into_iter().map(|page| {
            let style = if page == self.page { button::primary } else { button::text };
            button(text(page.title()).size(15))
                .on_press(Message::Navigate(page))
                .style(style)
                .width(Fill)
                .padding([9, 16])
                .into()
        });
        let brand = container(text("VoiceInk").size(20).font(style::bold())).padding([12, 16]);
        container(column![brand, Column::with_children(items).spacing(2)].padding([16, 8]))
            .width(Length::Fixed(NAV_WIDTH))
            .height(Fill)
            .style(style::sidebar)
            .into()
    }

    fn footer(&self) -> Element<'_, Message> {
        let status: Element<'_, Message> = match &self.status {
            Some(status) if status.is_error => text(&status.text).style(text::danger).into(),
            Some(status) => text(&status.text).style(text::success).into(),
            None => space().into(),
        };
        row![
            container(status).width(Fill),
            button("Save").on_press(Message::Save).style(button::primary).padding([8, 24]),
            button("Close").on_press(Message::Close).style(button::secondary).padding([8, 24]),
        ]
        .spacing(8)
        .align_y(iced::Center)
        .into()
    }
}
