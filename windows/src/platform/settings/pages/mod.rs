//! One type per settings page behind the [`Page`] trait.
//!
//! Pages communicate only through the window's working copy of the
//! [`Config`]: they show it in [`Page::load`] / [`Page::enter`] and write
//! their fields back in [`Page::apply`] when the user saves.

mod command;
mod dashboard;
mod dictionary;
mod enhancement;
mod general;
mod history;
mod output;
mod prompts;
mod snippets;
mod transcription;

use super::widgets::{Builder, Edit, Label};
use crate::config::Config;
use crate::context::AppContext;
use crate::settings_page::SettingsPage;
use windows::Win32::Foundation::HWND;

/// What a page may use besides the configuration.
pub struct PageContext<'a> {
    pub app: &'a AppContext,
    /// The settings window, as owner for message boxes.
    pub window: HWND,
    /// One-line feedback next to the Save button.
    pub status: Label,
}

/// API keys typed on a page, stored after the configuration was saved.
pub type KeyChanges = Vec<(&'static str, String)>;

pub trait Page {
    /// Shows `config` in the controls (when the window opens).
    fn load(&mut self, _config: &Config, _cx: &PageContext<'_>) {}

    /// Validates the controls and writes them into `config`.
    ///
    /// # Errors
    /// Returns a user-facing message naming the invalid field.
    fn apply(&mut self, _config: &mut Config, _keys: &mut KeyChanges) -> Result<(), String> {
        Ok(())
    }

    /// The page becomes visible; other pages may have changed `config`.
    fn enter(&mut self, _config: &Config, _cx: &PageContext<'_>) {}

    /// The page is hidden; keeps edits other pages depend on.
    fn leave(&mut self, _config: &mut Config) {}

    /// A button or list of this page was used (`id` is page-relative).
    fn command(&mut self, _id: u16, _code: u32, _config: &mut Config, _cx: &PageContext<'_>) {}

    /// The configuration and keys were written.
    fn saved(&mut self, _cx: &PageContext<'_>) {}

    /// A dictation finished and the history changed.
    fn history_changed(&mut self, _cx: &PageContext<'_>) {}
}

/// Creates the controls of `page`.
pub fn build(page: SettingsPage, b: &mut Builder<'_>) -> Box<dyn Page> {
    b.title(page.title());
    match page {
        SettingsPage::Dashboard => Box::new(dashboard::Dashboard::build(b)),
        SettingsPage::General => Box::new(general::General::build(b)),
        SettingsPage::Transcription => Box::new(transcription::Transcription::build(b)),
        SettingsPage::Enhancement => Box::new(enhancement::Enhancement::build(b)),
        SettingsPage::Prompts => Box::new(prompts::Prompts::build(b)),
        SettingsPage::Dictionary => Box::new(dictionary::Dictionary::build(b)),
        SettingsPage::Snippets => Box::new(snippets::Snippets::build(b)),
        SettingsPage::CommandMode => Box::new(command::CommandMode::build(b)),
        SettingsPage::Output => Box::new(output::Output::build(b)),
        SettingsPage::History => Box::new(history::History::build(b)),
    }
}

/// An API key field with its status label, shared by the provider pages.
#[derive(Debug, Clone, Copy, Default)]
struct KeyField {
    edit: Edit,
    status: Label,
}

impl KeyField {
    const CUE_STORED: &'static str = "stored — type to replace";
    const CUE_MISSING: &'static str = "paste your API key";

    fn show(self, credential: Option<&str>, cx: &PageContext<'_>) {
        let stored = credential.is_some_and(|name| cx.app.secrets.has(name));
        self.status.set(match credential {
            None => "Not needed",
            Some(_) if stored => "Stored",
            Some(_) => "Not set",
        });
        self.edit.set_cue(if stored { Self::CUE_STORED } else { Self::CUE_MISSING });
    }

    fn collect(self, credential: Option<&'static str>, keys: &mut KeyChanges) {
        let key = self.edit.trimmed();
        if let Some(name) = credential.filter(|_| !key.is_empty()) {
            keys.push((name, key));
        }
    }

    fn remove(self, credential: Option<&str>, cx: &PageContext<'_>) {
        if let Some(name) = credential {
            match cx.app.secrets.remove(name) {
                Ok(()) => cx.status.set(&format!("Removed the {name} API key")),
                Err(e) => cx.status.set(&e.to_string()),
            }
        }
        self.edit.set("");
        self.show(credential, cx);
    }
}

/// An optional value typed into a field; empty means "use the default".
fn optional(text: String) -> Option<String> {
    (!text.is_empty()).then_some(text)
}

/// A model typed into a combo box; the provider default is stored as `None`.
fn model_override(text: String, default: &str) -> Option<String> {
    optional(text).filter(|model| model != default)
}

/// Model list for a combo box (the default model when the provider lists none).
fn models_or_default(models: &[&'static str], default: &'static str) -> Vec<&'static str> {
    if models.is_empty() && !default.is_empty() { vec![default] } else { models.to_vec() }
}
