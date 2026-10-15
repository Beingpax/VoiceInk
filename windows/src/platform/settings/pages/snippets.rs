//! Voice shortcuts that expand to saved text.

use super::super::widgets::{Builder, CLIENT_H, CONTENT_W, Edit, LEFT};
use super::{KeyChanges, Page, PageContext};
use crate::config::Config;
use crate::text::snippets;

pub struct Snippets {
    lines: Edit,
}

impl Snippets {
    pub fn build(b: &mut Builder<'_>) -> Self {
        b.text(
            "Say a trigger phrase and VoiceInk types the saved text. Saying only the trigger inserts the snippet \
             as-is; inside a longer dictation it is expanded after AI clean-up.",
            (LEFT, 56, CONTENT_W, 40),
        );
        b.label("One per line:  trigger => text    (\\n = line break, {date} {time} {datetime})", LEFT, 98, CONTENT_W);
        let lines = b.multiline((LEFT, 126, CONTENT_W, CLIENT_H - 126 - 92));
        b.text("Example:  my calendar link => https://cal.com/yourname", (LEFT, CLIENT_H - 82, CONTENT_W, 20));
        Self { lines }
    }
}

impl Page for Snippets {
    fn load(&mut self, config: &Config, _cx: &PageContext<'_>) {
        self.lines.set(&snippets::format_lines(&config.snippets));
    }

    fn apply(&mut self, config: &mut Config, _keys: &mut KeyChanges) -> Result<(), String> {
        config.snippets = snippets::parse_lines(&self.lines.text()).map_err(|e| format!("Snippets: {e}"))?;
        Ok(())
    }
}
