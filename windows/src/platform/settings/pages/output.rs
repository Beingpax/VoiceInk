//! How text is inserted into the focused app.

use super::super::widgets::{Builder, CheckBox, ComboBox, Edit, HINT_GAP, ROW, TOP};
use super::{KeyChanges, Page, PageContext};
use crate::config::{Config, PasteMethod, SendKey};

const PASTE_METHODS: [(PasteMethod, &str); 3] = [
    (PasteMethod::CtrlV, "Clipboard + Ctrl+V (recommended)"),
    (PasteMethod::ShiftInsert, "Clipboard + Shift+Insert (terminals)"),
    (PasteMethod::Type, "Simulated typing (no clipboard)"),
];
const SEND_KEYS: [(SendKey, &str); 4] = [
    (SendKey::None, "Nothing"),
    (SendKey::Enter, "Enter"),
    (SendKey::ShiftEnter, "Shift+Enter"),
    (SendKey::CtrlEnter, "Ctrl+Enter"),
];

pub struct Output {
    method: ComboBox,
    restore: CheckBox,
    restore_delay: Edit,
    send_key: ComboBox,
    append_space: CheckBox,
}

impl Output {
    pub fn build(b: &mut Builder<'_>) -> Self {
        let mut y = TOP;
        b.row_label("Insert text with", y);
        let method = b.combo(y, 320, false, 0);
        y += ROW + 4;
        let restore = b.option("Restore my clipboard after pasting", y);
        y += ROW;
        b.row_label("Restore after (ms)", y);
        let restore_delay = b.number(y, 100);
        y += ROW;
        b.row_label("Then press", y);
        let send_key = b.combo(y, 200, false, 0);
        y += HINT_GAP;
        b.hint("\"Finish & Send\": submit chat messages automatically", y);
        y += ROW;
        let append_space = b.option("Add a trailing space after each dictation", y);
        Self { method, restore, restore_delay, send_key, append_space }
    }
}

impl Page for Output {
    fn load(&mut self, config: &Config, _cx: &PageContext<'_>) {
        let output = &config.output;
        self.method.show_choices(&PASTE_METHODS, output.method);
        self.restore.set(output.restore_clipboard);
        self.restore_delay.set(&output.clipboard_restore_delay_ms.to_string());
        self.send_key.show_choices(&SEND_KEYS, output.send_key);
        self.append_space.set(output.append_space);
    }

    fn apply(&mut self, config: &mut Config, _keys: &mut KeyChanges) -> Result<(), String> {
        let output = &mut config.output;
        output.method = self.method.choice(&PASTE_METHODS);
        output.restore_clipboard = self.restore.checked();
        output.clipboard_restore_delay_ms = self.restore_delay.number("Restore delay")?;
        output.send_key = self.send_key.choice(&SEND_KEYS);
        output.append_space = self.append_space.checked();
        Ok(())
    }
}
