//! Editor for the AI Enhancement prompts.

use super::super::widgets::{
    Builder, CBN_SELCHANGE, CLIENT_H, CONTENT_W, CheckBox, ComboBox, Edit, FIELD_W, FIELD_X, LABEL_W, LEFT, ROW,
    Severity, TOP, message_box,
};
use super::{Page, PageContext};
use crate::config::Config;
use crate::prompts::CustomPrompt;

const ID_SELECT: u16 = 1;
const ID_NEW: u16 = 2;
const ID_DELETE: u16 = 3;

pub struct Prompts {
    select: ComboBox,
    title: Edit,
    system_rules: CheckBox,
    text: Edit,
    /// Index into `config.prompts` shown in the editor.
    current: usize,
}

impl Prompts {
    pub fn build(b: &mut Builder<'_>) -> Self {
        let y = TOP;
        b.row_label("Prompt", y);
        let select = b.combo(y, 280, false, ID_SELECT);
        b.button("New", FIELD_X + 288, y - 2, 76, ID_NEW);
        b.button("Delete", FIELD_X + 372, y - 2, 80, ID_DELETE);
        b.row_label("Title", y + ROW);
        let title = b.edit(y + ROW, 280);
        let system_rules =
            b.check("Wrap with VoiceInk's transcription-cleaning rules (recommended)", FIELD_X, y + 2 * ROW, FIELD_W);
        b.label("Instructions", LEFT, y + 3 * ROW, LABEL_W);
        let text_top = y + 3 * ROW + 26;
        let text = b.multiline((LEFT, text_top, CONTENT_W, CLIENT_H - text_top - 60));
        Self { select, title, system_rules, text, current: 0 }
    }

    fn show(&mut self, config: &Config) {
        self.current = self.current.min(config.prompts.len().saturating_sub(1));
        self.select.fill(config.prompts.iter().map(|p| p.title.as_str()));
        self.select.select(self.current);
        if let Some(prompt) = config.prompts.get(self.current) {
            self.title.set(&prompt.title);
            self.system_rules.set(prompt.use_system_instructions);
            self.text.set(&prompt.prompt_text);
        }
    }

    /// Copies the editor back into the working configuration.
    fn store(&self, config: &mut Config) {
        let Some(prompt) = config.prompts.get_mut(self.current) else { return };
        let title = self.title.trimmed();
        if !title.is_empty() {
            prompt.title = title;
        }
        prompt.prompt_text = self.text.text();
        prompt.use_system_instructions = self.system_rules.checked();
    }
}

impl Page for Prompts {
    fn load(&mut self, config: &Config, _cx: &PageContext<'_>) {
        self.current = config.prompts.iter().position(|p| p.id == config.enhancement.prompt_id).unwrap_or(0);
        self.show(config);
    }

    fn apply(&mut self, config: &mut Config, _keys: &mut super::KeyChanges) -> Result<(), String> {
        self.store(config);
        Ok(())
    }

    fn enter(&mut self, config: &Config, _cx: &PageContext<'_>) {
        self.show(config);
    }

    fn leave(&mut self, config: &mut Config) {
        self.store(config);
    }

    fn command(&mut self, id: u16, code: u32, config: &mut Config, cx: &PageContext<'_>) {
        match (id, code) {
            (ID_SELECT, CBN_SELCHANGE) => {
                self.store(config);
                self.current = self.select.selected().unwrap_or(0);
            }
            (ID_NEW, _) => {
                self.store(config);
                config.prompts.push(CustomPrompt::new_user_prompt());
                self.current = config.prompts.len() - 1;
            }
            (ID_DELETE, _) if config.prompts.len() <= 1 => {
                return message_box(cx.window, "At least one prompt is required.", Severity::Warning);
            }
            (ID_DELETE, _) => {
                config.prompts.remove(self.current);
            }
            _ => return,
        }
        self.show(config);
    }
}
