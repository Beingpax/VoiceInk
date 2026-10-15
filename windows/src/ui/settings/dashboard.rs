//! Statistics and recent transcriptions.

use super::super::style::{self, ACCENT, EMPTY_BAR, MUTED, bold, semibold};
use super::form::{Env, Status};
use crate::history::{Entry, Status as EntryStatus};
use crate::stats::{self, Stats};
use iced::widget::{Column, button, column, container, row, scrollable, space, text};
use iced::{Element, Fill, FillPortion, Length};

const CHART_DAYS: usize = 14;
const RECENT_LIMIT: usize = 100;
const PREVIEW_CHARS: usize = 140;
const TILE_HEIGHT: f32 = 96.0;
const CHART_HEIGHT: f32 = 150.0;

#[derive(Debug, Default)]
pub struct Dashboard {
    stats: Stats,
    /// Completed entries, newest first.
    recent: Vec<Entry>,
}

#[derive(Debug, Clone, Copy)]
pub enum Message {
    Refresh,
    Copy(usize),
    Export,
}

impl Dashboard {
    pub fn refresh(&mut self, env: Env<'_>) {
        let entries = env.app.history.load();
        self.stats = stats::compute_now(&entries, CHART_DAYS);
        self.recent =
            entries.into_iter().rev().filter(|e| e.status == EntryStatus::Completed).take(RECENT_LIMIT).collect();
    }

    pub fn update(&mut self, message: Message, env: Env<'_>) -> Option<Status> {
        match message {
            Message::Refresh => {
                self.refresh(env);
                None
            }
            Message::Copy(index) => {
                let entry = self.recent.get(index)?;
                Some(match env.desktop.copy_text(entry.final_text()) {
                    Ok(()) => Status::info("Copied to the clipboard"),
                    Err(e) => Status::error(e),
                })
            }
            Message::Export => Some(export_history(env)),
        }
    }

    pub fn view(&self) -> Element<'_, Message> {
        column![
            self.tiles(),
            row![self.chart(), self.top_apps()].spacing(12).height(Length::Fixed(CHART_HEIGHT + 60.0)),
            row![
                text("Recent transcriptions").font(semibold()).width(Fill),
                button("Refresh").on_press(Message::Refresh).style(button::secondary),
                button("Export CSV").on_press(Message::Export).style(button::secondary),
            ]
            .spacing(8)
            .align_y(iced::Center),
            self.recent_list(),
        ]
        .spacing(style::SECTION_SPACING)
        .into()
    }

    fn tiles(&self) -> Element<'_, Message> {
        let s = &self.stats;
        let plural = if s.streak_days == 1 { "" } else { "s" };
        let tiles = [
            ("Words dictated", stats::format_count(s.words), format!("{} sessions", stats::format_count(s.sessions))),
            (
                "Time saved",
                stats::format_duration(s.time_saved_secs),
                format!("vs typing at {} WPM", stats::TYPING_WPM),
            ),
            (
                "Speaking speed",
                format!("{:.0} WPM", s.wpm),
                format!("{} recorded", stats::format_duration(s.duration_secs)),
            ),
            (
                "Streak",
                format!("{} day{plural}", s.streak_days),
                format!("{} AI-enhanced", stats::format_count(s.enhanced_sessions)),
            ),
        ];
        let tiles = tiles.into_iter().enumerate().map(|(i, (label, value, detail))| {
            let value = text(value).size(26).font(bold()).color_maybe((i == 1).then_some(ACCENT));
            container(column![text(label).size(13).color(MUTED), value, text(detail).size(13).color(MUTED)].spacing(2))
                .padding(14)
                .width(Fill)
                .height(Length::Fixed(TILE_HEIGHT))
                .style(style::tile)
                .into()
        });
        row(tiles).spacing(12).into()
    }

    /// Words per day as a bar chart, oldest day on the left.
    #[allow(clippy::cast_precision_loss, reason = "word counts are far below f32's exact range")]
    fn chart(&self) -> Element<'_, Message> {
        let days = &self.stats.daily_words;
        let max = days.iter().map(|d| d.1).max().unwrap_or(0).max(1);
        let bars = days.iter().enumerate().map(|(i, (date, words))| {
            let height = (*words as f32 / max as f32 * CHART_HEIGHT).max(2.0);
            let color = if *words > 0 { ACCENT } else { EMPTY_BAR };
            let bar = container(space()).width(Fill).height(Length::Fixed(height)).style(move |_| container::Style {
                background: Some(color.into()),
                border: iced::Border { radius: 3.0.into(), ..Default::default() },
                ..Default::default()
            });
            // Label every other day, always including today.
            let labeled = i % 2 == (days.len() + 1) % 2 || i + 1 == days.len();
            let label = text(if labeled { date.format("%d").to_string() } else { String::new() }).size(11).color(MUTED);
            column![space().height(Fill), bar, label].align_x(iced::Center).spacing(4).width(Fill).into()
        });
        let heading = text("Words per day — last 14 days").font(semibold());
        container(column![heading, row(bars).spacing(6).height(Fill)].spacing(8))
            .padding(14)
            .width(FillPortion(2))
            .height(Fill)
            .style(style::tile)
            .into()
    }

    fn top_apps(&self) -> Element<'_, Message> {
        let mut list = Column::new().spacing(6).push(text("Top apps").font(semibold()));
        if self.stats.top_apps.is_empty() {
            list = list.push(text("Dictate something to see stats").color(MUTED));
        }
        for (app, count) in &self.stats.top_apps {
            list =
                list.push(row![text(app.trim_end_matches(".exe")).width(Fill), text(count.to_string()).color(MUTED)]);
        }
        container(list).padding(14).width(FillPortion(1)).height(Fill).style(style::tile).into()
    }

    fn recent_list(&self) -> Element<'_, Message> {
        if self.recent.is_empty() {
            return style::hint("No transcriptions yet.");
        }
        let rows = self.recent.iter().enumerate().map(|(i, entry)| {
            let preview: String = entry.final_text().replace(['\r', '\n'], " ").chars().take(PREVIEW_CHARS).collect();
            row![
                text(entry.timestamp.format("%b %d  %H:%M").to_string()).size(13).color(MUTED).width(110),
                text(entry.app.as_deref().unwrap_or("—").to_string()).size(13).color(MUTED).width(110),
                text(preview).size(14).width(Fill),
                button(text("Copy").size(13)).on_press(Message::Copy(i)).style(button::text),
            ]
            .spacing(8)
            .align_y(iced::Center)
            .into()
        });
        scrollable(Column::with_children(rows).spacing(4).padding([0, 12])).height(Length::Fixed(220.0)).into()
    }
}

/// Exports the history to `history.csv` in the data folder and opens it.
pub fn export_history(env: Env<'_>) -> Status {
    let out = env.app.paths.history_csv();
    match env.app.history.export_csv_file(&out) {
        Ok(count) => {
            env.desktop.open_path(&out);
            Status::info(format!("Exported {count} entries to {}", out.display()))
        }
        Err(e) => Status::error(format!("Export failed: {e}")),
    }
}
