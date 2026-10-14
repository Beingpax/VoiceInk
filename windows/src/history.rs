//! Transcription history (the SwiftData `Transcription` model), stored as
//! JSON Lines in `%APPDATA%\VoiceInk\history.jsonl`.

use serde::{Deserialize, Serialize};
use std::io::{BufRead, Write};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Status {
    Completed,
    Failed,
    Canceled,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Entry {
    pub id: String,
    pub timestamp: chrono::DateTime<chrono::Local>,
    pub status: Status,
    /// Cleaned transcript (after filtering, formatting and replacements).
    pub text: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub enhanced_text: Option<String>,
    /// Recording length in seconds.
    pub duration: f64,
    pub transcription_model: String,
    pub transcription_secs: f64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub enhancement_model: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub prompt_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub enhancement_secs: Option<f64>,
    /// Text that was actually inserted when it differs from `text` and
    /// `enhanced_text` (snippet expansion, Command Mode).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub delivered_text: Option<String>,
    /// Why AI enhancement failed (the plain transcript was delivered instead).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub enhancement_error: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mode_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub app: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub audio_file: Option<PathBuf>,
}

impl Entry {
    pub fn new(status: Status) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            timestamp: chrono::Local::now(),
            status,
            text: String::new(),
            enhanced_text: None,
            duration: 0.0,
            transcription_model: String::new(),
            transcription_secs: 0.0,
            enhancement_model: None,
            prompt_name: None,
            enhancement_secs: None,
            enhancement_error: None,
            delivered_text: None,
            mode_name: None,
            app: None,
            audio_file: None,
        }
    }

    /// The text that was delivered to the user.
    pub fn final_text(&self) -> &str {
        self.delivered_text
            .as_deref()
            .or(self.enhanced_text.as_deref())
            .filter(|t| !t.is_empty())
            .unwrap_or(&self.text)
    }
}

pub fn history_path() -> PathBuf {
    crate::config::data_dir().join("history.jsonl")
}

pub fn recordings_dir() -> PathBuf {
    crate::config::data_dir().join("recordings")
}

pub fn append(path: &Path, entry: &Entry) -> std::io::Result<()> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let mut file = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)?;
    let line = serde_json::to_string(entry).map_err(std::io::Error::other)?;
    writeln!(file, "{line}")
}

/// Loads every readable entry, oldest first. Corrupt lines are skipped.
pub fn load(path: &Path) -> Vec<Entry> {
    let Ok(file) = std::fs::File::open(path) else {
        return Vec::new();
    };
    std::io::BufReader::new(file)
        .lines()
        .map_while(Result::ok)
        .filter_map(|l| serde_json::from_str(&l).ok())
        .collect()
}

/// Most recent successfully delivered text.
pub fn last_text(path: &Path) -> Option<String> {
    load(path)
        .into_iter()
        .rev()
        .find(|e| e.status == Status::Completed && !e.final_text().is_empty())
        .map(|e| e.final_text().to_string())
}

/// Drops the oldest entries (and their audio files) beyond `max_entries`.
pub fn trim(path: &Path, max_entries: usize) -> std::io::Result<()> {
    if max_entries == 0 {
        return Ok(());
    }
    let entries = load(path);
    if entries.len() <= max_entries {
        return Ok(());
    }
    let (old, keep) = entries.split_at(entries.len() - max_entries);
    for e in old {
        if let Some(audio) = &e.audio_file {
            let _ = std::fs::remove_file(audio);
        }
    }
    let tmp = path.with_extension("jsonl.tmp");
    {
        let mut f = std::fs::File::create(&tmp)?;
        for e in keep {
            writeln!(
                f,
                "{}",
                serde_json::to_string(e).map_err(std::io::Error::other)?
            )?;
        }
    }
    std::fs::rename(tmp, path)
}

/// Writes history as CSV (like the macOS "Export" action).
pub fn export_csv(entries: &[Entry], out: &mut impl Write) -> std::io::Result<()> {
    fn esc(s: &str) -> String {
        format!("\"{}\"", s.replace('"', "\"\""))
    }
    writeln!(
        out,
        "timestamp,status,duration_s,mode,app,model,text,enhanced_text"
    )?;
    for e in entries {
        writeln!(
            out,
            "{},{:?},{:.1},{},{},{},{},{}",
            e.timestamp.to_rfc3339(),
            e.status,
            e.duration,
            esc(e.mode_name.as_deref().unwrap_or("")),
            esc(e.app.as_deref().unwrap_or("")),
            esc(&e.transcription_model),
            esc(&e.text),
            esc(e.enhanced_text.as_deref().unwrap_or("")),
        )?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn append_load_trim() {
        let dir = std::env::temp_dir().join(format!("voiceink-hist-{}", uuid::Uuid::new_v4()));
        let path = dir.join("history.jsonl");
        for i in 0..5 {
            let mut e = Entry::new(Status::Completed);
            e.text = format!("t{i}");
            append(&path, &e).unwrap();
        }
        let mut failed = Entry::new(Status::Failed);
        failed.text = "Transcription Failed".into();
        append(&path, &failed).unwrap();

        assert_eq!(load(&path).len(), 6);
        assert_eq!(last_text(&path).as_deref(), Some("t4"));
        trim(&path, 3).unwrap();
        let left = load(&path);
        assert_eq!(left.len(), 3);
        assert_eq!(left[0].text, "t3");

        let mut csv = Vec::new();
        export_csv(&left, &mut csv).unwrap();
        assert!(String::from_utf8(csv).unwrap().lines().count() == 4);
        std::fs::remove_dir_all(dir).ok();
    }

    #[test]
    fn final_text_prefers_enhanced() {
        let mut e = Entry::new(Status::Completed);
        e.text = "raw".into();
        assert_eq!(e.final_text(), "raw");
        e.enhanced_text = Some("nice".into());
        assert_eq!(e.final_text(), "nice");
    }
}
