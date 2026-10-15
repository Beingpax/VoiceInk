//! Custom vocabulary and word replacements.

use super::super::widgets::{Builder, CLIENT_H, CONTENT_W, Edit, LEFT};
use super::{KeyChanges, Page, PageContext};
use crate::config::Config;
use crate::text::{format_replacement_lines, parse_replacement_lines};

const COLUMN_GAP: i32 = 16;

pub struct Dictionary {
    vocabulary: Edit,
    replacements: Edit,
}

impl Dictionary {
    pub fn build(b: &mut Builder<'_>) -> Self {
        let half = (CONTENT_W - COLUMN_GAP) / 2;
        let right = LEFT + half + COLUMN_GAP;
        b.label("Vocabulary — one term per line", LEFT, 60, half);
        b.label("Replacements — one per line: spoken -> written", right, 60, half);
        let vocabulary = b.multiline((LEFT, 86, half, CLIENT_H - 86 - 92));
        let replacements = b.multiline((right, 86, half, CLIENT_H - 86 - 92));
        b.text(
            "Vocabulary guides spelling of names. Example replacement: voice ink, voice inc -> VoiceInk",
            (LEFT, CLIENT_H - 82, CONTENT_W, 20),
        );
        Self { vocabulary, replacements }
    }
}

impl Page for Dictionary {
    fn load(&mut self, config: &Config, _cx: &PageContext<'_>) {
        self.vocabulary.set(&config.vocabulary.join("\n"));
        self.replacements.set(&format_replacement_lines(&config.replacements));
    }

    fn apply(&mut self, config: &mut Config, _keys: &mut KeyChanges) -> Result<(), String> {
        config.vocabulary =
            self.vocabulary.text().lines().map(str::trim).filter(|l| !l.is_empty()).map(str::to_string).collect();
        config.replacements =
            parse_replacement_lines(&self.replacements.text()).map_err(|e| format!("Replacements: {e}"))?;
        Ok(())
    }
}
