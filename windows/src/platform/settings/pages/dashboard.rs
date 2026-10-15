//! Statistics and recent transcriptions.

use super::super::stats_panel;
use super::super::widgets::{Builder, CLIENT_H, CONTENT_W, LBN_DBLCLK, LEFT, ListBox};
use super::{Page, PageContext};
use crate::config::Config;
use crate::history::{Entry, Status};
use crate::platform::{actions, clipboard};
use crate::stats;
use windows::Win32::Foundation::HWND;

const ID_RECENT: u16 = 1;
const ID_REFRESH: u16 = 2;
const ID_EXPORT: u16 = 3;

const CHART_DAYS: usize = 14;
const RECENT_LIMIT: usize = 100;
const PREVIEW_CHARS: usize = 140;

pub struct Dashboard {
    panel: HWND,
    recent: ListBox,
    /// The entries shown in `recent`, in display order.
    entries: Vec<Entry>,
}

impl Dashboard {
    pub fn build(b: &mut Builder<'_>) -> Self {
        let panel = b.custom(stats_panel::CLASS, (LEFT, 56, CONTENT_W, 300));
        b.label("Recent transcriptions — double-click to copy", LEFT, 364, 420);
        b.button("Refresh", LEFT + CONTENT_W - 220, 362, 100, ID_REFRESH);
        b.button("Export CSV", LEFT + CONTENT_W - 112, 362, 112, ID_EXPORT);
        let recent = b.list((LEFT, 396, CONTENT_W, CLIENT_H - 396 - 60), ID_RECENT, true);
        Self { panel, recent, entries: Vec::new() }
    }

    fn refresh(&mut self, cx: &PageContext<'_>) {
        let entries = cx.app.history.load();
        stats_panel::update(self.panel, stats::compute_now(&entries, CHART_DAYS));
        self.entries = entries.into_iter().rev().filter(|e| e.status == Status::Completed).take(RECENT_LIMIT).collect();
        self.recent.fill(self.entries.iter().map(summary));
    }

    fn copy_selected(&self, cx: &PageContext<'_>) {
        let Some(entry) = self.recent.selected().and_then(|i| self.entries.get(i)) else { return };
        match clipboard::set_text(entry.final_text(), false) {
            Ok(_) => cx.status.set("Copied to the clipboard"),
            Err(e) => cx.status.set(&e.to_string()),
        }
    }
}

/// One line of the recent list: time, app and the start of the text.
fn summary(entry: &Entry) -> String {
    let text: String = entry.final_text().replace(['\r', '\n'], " ").chars().take(PREVIEW_CHARS).collect();
    format!("{}   {}   {text}", entry.timestamp.format("%b %d  %H:%M"), entry.app.as_deref().unwrap_or("—"))
}

impl Page for Dashboard {
    fn enter(&mut self, _config: &Config, cx: &PageContext<'_>) {
        self.refresh(cx);
    }

    fn command(&mut self, id: u16, code: u32, _config: &mut Config, cx: &PageContext<'_>) {
        match (id, code) {
            (ID_RECENT, LBN_DBLCLK) => self.copy_selected(cx),
            (ID_REFRESH, _) => self.refresh(cx),
            (ID_EXPORT, _) => {
                if let Err(e) = actions::open_history_csv(cx.app) {
                    cx.status.set(&format!("Export failed: {e}"));
                }
            }
            _ => {}
        }
    }

    fn history_changed(&mut self, cx: &PageContext<'_>) {
        self.refresh(cx);
    }
}
