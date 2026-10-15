//! Dashboard statistics computed from the history (port of `DashboardStatsModels`).

// Statistics over word counts, seconds and day offsets: the float/int
// conversions in this module are intentional and range-checked by design.
#![allow(
    clippy::cast_possible_truncation,
    clippy::cast_possible_wrap,
    clippy::cast_precision_loss,
    clippy::cast_sign_loss
)]

use crate::history::{Entry, Status};
use crate::text::word_count;
use chrono::{Duration, Local, NaiveDate, Timelike};

/// Same assumption as `DashboardTimeSaving.averageTypingSpeedWordsPerMinute`.
pub const TYPING_WPM: f64 = 40.0;

#[derive(Debug, Clone, Default, PartialEq)]
pub struct Stats {
    pub sessions: usize,
    pub words: usize,
    /// Total recorded audio, seconds.
    pub duration_secs: f64,
    /// Estimated typing time minus speaking time, seconds (never negative).
    pub time_saved_secs: f64,
    /// Speaking speed in words per minute.
    pub wpm: f64,
    pub enhanced_sessions: usize,
    /// Consecutive days with at least one dictation, ending today or yesterday.
    pub streak_days: usize,
    /// Words per day, oldest first, for the activity chart.
    pub daily_words: Vec<(NaiveDate, usize)>,
    /// Sessions per hour of day (0..24).
    pub hourly_sessions: [usize; 24],
    /// Most used applications: (process name, sessions).
    pub top_apps: Vec<(String, usize)>,
}

pub fn time_saved(words: usize, duration_secs: f64) -> f64 {
    (words as f64 / TYPING_WPM * 60.0 - duration_secs).max(0.0)
}

/// Aggregates completed entries; `days` controls the length of `daily_words`.
pub fn compute(entries: &[Entry], days: usize, today: NaiveDate) -> Stats {
    let mut s = Stats::default();
    let start = today - Duration::days(days.saturating_sub(1) as i64);
    let mut daily = vec![0usize; days];
    let mut active_days = std::collections::BTreeSet::new();
    let mut apps: std::collections::HashMap<String, usize> = std::collections::HashMap::new();

    for e in entries.iter().filter(|e| e.status == Status::Completed) {
        let words = word_count(e.final_text());
        s.sessions += 1;
        s.words += words;
        s.duration_secs += e.duration;
        if e.enhanced_text.as_deref().is_some_and(|t| !t.is_empty()) {
            s.enhanced_sessions += 1;
        }
        let date = e.timestamp.date_naive();
        active_days.insert(date);
        if date >= start && date <= today {
            daily[(date - start).num_days() as usize] += words;
        }
        s.hourly_sessions[e.timestamp.hour() as usize] += 1;
        if let Some(app) = e.app.as_ref().filter(|a| !a.is_empty()) {
            *apps.entry(app.clone()).or_default() += 1;
        }
    }

    s.time_saved_secs = time_saved(s.words, s.duration_secs);
    s.wpm = if s.duration_secs > 0.0 { s.words as f64 / (s.duration_secs / 60.0) } else { 0.0 };
    s.daily_words = daily.into_iter().enumerate().map(|(i, w)| (start + Duration::days(i as i64), w)).collect();

    // Streak counts back from today (or yesterday, so it survives until you dictate today).
    let mut day = if active_days.contains(&today) { today } else { today - Duration::days(1) };
    while active_days.contains(&day) {
        s.streak_days += 1;
        day -= Duration::days(1);
    }

    let mut top: Vec<(String, usize)> = apps.into_iter().collect();
    top.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
    top.truncate(5);
    s.top_apps = top;
    s
}

pub fn compute_now(entries: &[Entry], days: usize) -> Stats {
    compute(entries, days, Local::now().date_naive())
}

/// "1 h 05 min", "12 min", "45 s".
pub fn format_duration(secs: f64) -> String {
    let secs = secs.max(0.0).round() as u64;
    match secs {
        s if s >= 3600 => format!("{} h {:02} min", s / 3600, (s % 3600) / 60),
        s if s >= 60 => format!("{} min", s / 60),
        s => format!("{s} s"),
    }
}

/// "12,345".
pub fn format_count(n: usize) -> String {
    let digits = n.to_string();
    let mut out = String::new();
    for (i, c) in digits.chars().enumerate() {
        if i > 0 && (digits.len() - i).is_multiple_of(3) {
            out.push(',');
        }
        out.push(c);
    }
    out
}

#[cfg(test)]
#[allow(clippy::float_cmp, reason = "exact values are expected")]
mod tests {
    use super::*;
    use chrono::TimeZone;

    fn entry(day: u32, hour: u32, text: &str, secs: f64, app: &str) -> Entry {
        let mut e = Entry::new(Status::Completed);
        e.timestamp = Local.with_ymd_and_hms(2026, 10, day, hour, 0, 0).unwrap();
        e.text = text.into();
        e.duration = secs;
        e.app = Some(app.into());
        e
    }

    #[test]
    fn aggregates_history() {
        let today = NaiveDate::from_ymd_opt(2026, 10, 13).unwrap();
        let mut failed = entry(13, 9, "x y z", 5.0, "a.exe");
        failed.status = Status::Failed;
        let mut enhanced = entry(12, 9, "raw", 3.0, "slack.exe");
        enhanced.enhanced_text = Some("one two three four".into());
        let entries = vec![
            entry(13, 9, "one two three four five six", 6.0, "slack.exe"),
            enhanced,
            entry(11, 22, "a b", 2.0, "code.exe"),
            entry(1, 10, "old words here", 3.0, "code.exe"),
            failed,
        ];
        let s = compute(&entries, 7, today);
        assert_eq!(s.sessions, 4);
        assert_eq!(s.words, 6 + 4 + 2 + 3);
        assert_eq!(s.enhanced_sessions, 1);
        assert_eq!(s.streak_days, 3);
        assert_eq!(s.daily_words.len(), 7);
        assert_eq!(s.daily_words[6], (today, 6));
        assert_eq!(s.daily_words[5].1, 4);
        assert_eq!(s.hourly_sessions[9], 2);
        assert_eq!(s.top_apps[0], ("code.exe".to_string(), 2));
        assert!((s.wpm - 15.0 / (14.0 / 60.0)).abs() < 1e-9);
        assert!((s.time_saved_secs - (15.0 / 40.0 * 60.0 - 14.0)).abs() < 1e-9);
    }

    #[test]
    fn empty_history() {
        let s = compute(&[], 14, NaiveDate::from_ymd_opt(2026, 1, 1).unwrap());
        assert_eq!(s.sessions, 0);
        assert_eq!(s.wpm, 0.0);
        assert_eq!(s.streak_days, 0);
        assert_eq!(s.daily_words.len(), 14);
    }

    #[test]
    fn formats() {
        assert_eq!(time_saved(10, 60.0), 0.0);
        assert_eq!(format_duration(45.0), "45 s");
        assert_eq!(format_duration(125.0), "2 min");
        assert_eq!(format_duration(3900.0), "1 h 05 min");
        assert_eq!(format_count(1_234_567), "1,234,567");
        assert_eq!(format_count(12), "12");
    }
}
