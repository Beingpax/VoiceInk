//! History retention, export and deletion.

use super::super::widgets::{Builder, CHECK_ROW, CheckBox, Edit, FIELD_X, HINT_GAP, ROW, TOP, confirm};
use super::{KeyChanges, Page, PageContext};
use crate::config::Config;
use crate::platform::actions;

const ID_EXPORT: u16 = 1;
const ID_OPEN_FOLDER: u16 = 2;
const ID_CLEAR: u16 = 3;

pub struct History {
    enabled: CheckBox,
    save_audio: CheckBox,
    max_entries: Edit,
}

impl History {
    pub fn build(b: &mut Builder<'_>) -> Self {
        let mut y = TOP;
        let enabled = b.option("Keep a history of transcriptions", y);
        y += CHECK_ROW;
        let save_audio = b.option("Also keep the audio recordings", y);
        y += ROW;
        b.row_label("Keep at most (entries)", y);
        let max_entries = b.number(y, 100);
        y += HINT_GAP;
        b.hint("0 keeps everything", y);
        y += ROW + 8;
        b.button("Export CSV", FIELD_X, y, 130, ID_EXPORT);
        b.button("Open data folder", FIELD_X + 140, y, 150, ID_OPEN_FOLDER);
        b.button("Delete all history", FIELD_X + 300, y, 160, ID_CLEAR);
        Self { enabled, save_audio, max_entries }
    }
}

impl Page for History {
    fn load(&mut self, config: &Config, _cx: &PageContext<'_>) {
        self.enabled.set(config.history.enabled);
        self.save_audio.set(config.history.save_audio);
        self.max_entries.set(&config.history.max_entries.to_string());
    }

    fn apply(&mut self, config: &mut Config, _keys: &mut KeyChanges) -> Result<(), String> {
        config.history.enabled = self.enabled.checked();
        config.history.save_audio = self.save_audio.checked();
        config.history.max_entries = usize::try_from(self.max_entries.number("History size")?).unwrap_or(usize::MAX);
        Ok(())
    }

    fn command(&mut self, id: u16, _code: u32, _config: &mut Config, cx: &PageContext<'_>) {
        match id {
            ID_EXPORT => {
                if let Err(e) = actions::open_history_csv(cx.app) {
                    cx.status.set(&format!("Export failed: {e}"));
                }
            }
            ID_OPEN_FOLDER => actions::open_data_folder(cx.app),
            ID_CLEAR
                if confirm(cx.window, "Delete all transcriptions and saved recordings? This cannot be undone.") =>
            {
                match cx.app.history.clear() {
                    Ok(()) => cx.status.set("History deleted"),
                    Err(e) => cx.status.set(&format!("Could not delete the history: {e}")),
                }
            }
            _ => {}
        }
    }
}
