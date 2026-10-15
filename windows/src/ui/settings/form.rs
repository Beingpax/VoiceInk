//! Pieces shared by the settings pages: the environment they act on,
//! feedback for the status line, input parsing and the API-key field.

use super::super::Desktop;
use super::super::style::{FIELD_WIDTH, MUTED};
use crate::context::AppContext;
use crate::input::Hotkey;
use iced::widget::{button, row, text, text_input};
use iced::{Element, Length};

/// What a page may use besides the configuration.
#[derive(Clone, Copy)]
pub struct Env<'a> {
    pub app: &'a AppContext,
    pub desktop: &'a dyn Desktop,
}

/// One line of feedback next to the Save button.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Status {
    pub text: String,
    pub is_error: bool,
}

impl Status {
    pub fn info(text: impl Into<String>) -> Self {
        Self { text: text.into(), is_error: false }
    }

    pub fn error(text: impl Into<String>) -> Self {
        Self { text: text.into(), is_error: true }
    }
}

/// API keys typed on a page, stored after the configuration was saved.
pub type KeyChanges = Vec<(&'static str, String)>;

/// Parses a whole number typed into `field`.
///
/// # Errors
/// Returns a user-facing message naming the field.
pub fn number(value: &str, field: &str) -> Result<u64, String> {
    value.trim().parse().map_err(|_| format!("{field} must be a number"))
}

/// Like [`number`], for counts.
///
/// # Errors
/// Returns a user-facing message naming the field.
pub fn count(value: &str, field: &str) -> Result<usize, String> {
    number(value, field).map(|n| usize::try_from(n).unwrap_or(usize::MAX))
}

/// Validates a shortcut; empty is allowed when `optional`.
///
/// # Errors
/// Returns a user-facing message naming the shortcut.
pub fn shortcut(value: &str, name: &str, optional: bool) -> Result<String, String> {
    let spec = value.trim().to_string();
    if !(optional && spec.is_empty()) {
        spec.parse::<Hotkey>().map_err(|e| format!("{name} shortcut: {e}"))?;
    }
    Ok(spec)
}

/// An optional value typed into a field; empty means "use the default".
pub fn optional(value: &str) -> Option<String> {
    let value = value.trim();
    (!value.is_empty()).then(|| value.to_string())
}

/// A model typed by the user; the provider default is stored as `None`.
pub fn model_override(value: &str, default: &str) -> Option<String> {
    optional(value).filter(|model| model != default)
}

/// Non-empty, trimmed lines.
pub fn lines(value: &str) -> Vec<String> {
    value.lines().map(str::trim).filter(|l| !l.is_empty()).map(str::to_string).collect()
}

/// An API-key field for the provider currently selected on a page.
#[derive(Debug, Clone, Default)]
pub struct KeyField {
    /// What the user typed (never the stored key).
    pub input: String,
    stored: bool,
    needed: bool,
}

/// Events of a [`KeyField`].
#[derive(Debug, Clone)]
pub enum KeyMessage {
    Input(String),
    Remove,
}

impl KeyField {
    /// Shows whether `credential` (the selected provider's key) is stored.
    pub fn refresh(&mut self, credential: Option<&str>, env: Env<'_>) {
        self.needed = credential.is_some();
        self.stored = credential.is_some_and(|name| env.app.secrets.has(name));
    }

    pub fn update(&mut self, message: KeyMessage, credential: Option<&str>, env: Env<'_>) -> Option<Status> {
        match message {
            KeyMessage::Input(value) => {
                self.input = value;
                None
            }
            KeyMessage::Remove => {
                self.input.clear();
                let name = credential?;
                let status = match env.app.secrets.remove(name) {
                    Ok(()) => Status::info(format!("Removed the {name} API key")),
                    Err(e) => Status::error(e.to_string()),
                };
                self.refresh(credential, env);
                Some(status)
            }
        }
    }

    /// Queues the typed key for `credential`.
    pub fn collect(&self, credential: Option<&'static str>, keys: &mut KeyChanges) {
        if let (Some(name), Some(key)) = (credential, optional(&self.input)) {
            keys.push((name, key));
        }
    }

    /// The keys were written: clear the input and show the new state.
    pub fn saved(&mut self, credential: Option<&str>, env: Env<'_>) {
        self.input.clear();
        self.refresh(credential, env);
    }

    pub fn view(&self) -> Element<'_, KeyMessage> {
        let placeholder = if self.stored { "stored — type to replace" } else { "paste your API key" };
        let state = match (self.needed, self.stored) {
            (false, _) => "Not needed",
            (true, true) => "Stored",
            (true, false) => "Not set",
        };
        row![
            text_input(placeholder, &self.input)
                .secure(true)
                .on_input(KeyMessage::Input)
                .width(Length::Fixed(FIELD_WIDTH - 90.0)),
            button("Remove").on_press_maybe(self.stored.then_some(KeyMessage::Remove)).style(button::secondary),
            text(state).color(MUTED),
        ]
        .spacing(8)
        .align_y(iced::Center)
        .into()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_numbers_and_shortcuts() {
        assert_eq!(number(" 42 ", "Delay"), Ok(42));
        assert_eq!(number("x", "Delay"), Err("Delay must be a number".into()));
        assert_eq!(shortcut("", "Cancel", true), Ok(String::new()));
        assert!(shortcut("", "Record", false).is_err());
        assert_eq!(shortcut(" F9 ", "Record", false), Ok("F9".into()));
        assert!(shortcut("Ctrl+Nope", "Record", false).unwrap_err().starts_with("Record shortcut"));
    }

    #[test]
    fn optional_values_drop_defaults() {
        assert_eq!(optional("  "), None);
        assert_eq!(model_override("whisper-1", "whisper-1"), None);
        assert_eq!(model_override(" gpt ", "whisper-1"), Some("gpt".into()));
        assert_eq!(lines(" a \n\n b"), vec!["a", "b"]);
    }
}
