//! Command Mode: spoken instructions applied to the selected text.

use super::super::widgets::{Builder, CBN_SELCHANGE, CONTENT_W, CheckBox, ComboBox, Edit, HINT_GAP, LEFT, ROW};
use super::{KeyChanges, Page, PageContext, optional};
use crate::config::{Config, EnhancementProvider};
use crate::input::Hotkey;

const ID_PROVIDER: u16 = 1;
const SAME_AS_ENHANCEMENT: &str = "Same as AI Enhancement";

pub struct CommandMode {
    enabled: CheckBox,
    hotkey: Edit,
    provider: ComboBox,
    model: ComboBox,
}

impl CommandMode {
    pub fn build(b: &mut Builder<'_>) -> Self {
        b.text(
            "Select text in any app, press the Command shortcut and say what to do — \"make this more formal\", \
             \"translate to German\", \"turn this into bullet points\". The result replaces the selection. With \
             nothing selected, the instruction writes new text at the cursor (\"write a polite reply declining the \
             meeting\").",
            (LEFT, 56, CONTENT_W, 58),
        );
        let mut y = 128;
        let enabled = b.option("Enable Command Mode", y);
        y += ROW;
        b.row_label("Command shortcut", y);
        let hotkey = b.edit(y, 200);
        y += HINT_GAP;
        b.hint("Uses the same tap / hold behaviour as the record shortcut", y);
        y += ROW;
        b.row_label("AI provider", y);
        let provider = b.combo(y, 280, false, ID_PROVIDER);
        y += ROW;
        b.row_label("Model", y);
        let model = b.combo(y, 280, true, 0);
        y += HINT_GAP;
        b.hint("Leave empty for the provider's default. A capable model works best.", y);
        Self { enabled, hotkey, provider, model }
    }

    /// `None` = same provider as AI Enhancement (the first row).
    fn selected_provider(&self) -> Option<EnhancementProvider> {
        self.provider.selected().filter(|&row| row > 0).and_then(|row| EnhancementProvider::ALL.get(row - 1).copied())
    }

    fn provider_changed(&self, model: Option<&str>) {
        self.model.fill(self.selected_provider().map(EnhancementProvider::models).unwrap_or_default());
        self.model.set_text(model.unwrap_or(""));
    }
}

impl Page for CommandMode {
    fn load(&mut self, config: &Config, _cx: &PageContext<'_>) {
        let settings = &config.command;
        self.enabled.set(settings.enabled);
        self.hotkey.set(&settings.hotkey);
        self.provider.fill(
            std::iter::once(SAME_AS_ENHANCEMENT).chain(EnhancementProvider::ALL.iter().map(|p| p.display_name())),
        );
        let row =
            settings.provider.and_then(|p| EnhancementProvider::ALL.iter().position(|x| *x == p)).map_or(0, |i| i + 1);
        self.provider.select(row);
        self.provider_changed(settings.model.as_deref());
    }

    /// Runs after the General page, so the record shortcut is already updated.
    fn apply(&mut self, config: &mut Config, _keys: &mut KeyChanges) -> Result<(), String> {
        let enabled = self.enabled.checked();
        let hotkey = self.hotkey.trimmed();
        if enabled {
            let parsed = hotkey.parse::<Hotkey>().map_err(|e| format!("Command shortcut: {e}"))?;
            if config.hotkeys.record.parse::<Hotkey>().is_ok_and(|record| record == parsed) {
                return Err("The Command shortcut must differ from the record shortcut".into());
            }
        }
        let settings = &mut config.command;
        settings.enabled = enabled;
        settings.hotkey = hotkey;
        settings.provider = self.selected_provider();
        settings.model = optional(self.model.text());
        Ok(())
    }

    fn command(&mut self, id: u16, code: u32, _config: &mut Config, _cx: &PageContext<'_>) {
        if (id, code) == (ID_PROVIDER, CBN_SELCHANGE) {
            self.provider_changed(None);
        }
    }
}
