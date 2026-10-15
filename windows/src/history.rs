//! Transcription history (the `SwiftData` `Transcription` model), stored as
//! JSON Lines in `%APPDATA%\VoiceInk\history.jsonl`.

use crate::audio::TARGET_SAMPLE_RATE;
use crate::audio::wav::encode_wav_i16;
use crate::config::HistorySettings;
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
        self.delivered_text.as_deref().or(self.enhanced_text.as_deref()).filter(|t| !t.is_empty()).unwrap_or(&self.text)
    }
}

/// The history log: one JSON object per line, oldest first.
#[derive(Debug, Clone)]
pub struct HistoryStore {
    path: PathBuf,
    recordings: PathBuf,
}

impl HistoryStore {
    pub fn new(path: PathBuf, recordings: PathBuf) -> Self {
        Self { path, recordings }
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    /// Appends one entry.
    ///
    /// # Errors
    /// Returns an I/O error when the log cannot be written.
    pub fn append(&self, entry: &Entry) -> std::io::Result<()> {
        if let Some(dir) = self.path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        let mut file = std::fs::OpenOptions::new().create(true).append(true).open(&self.path)?;
        let line = serde_json::to_string(entry).map_err(std::io::Error::other)?;
        writeln!(file, "{line}")
    }

    /// Loads every readable entry, oldest first. Corrupt lines are skipped.
    pub fn load(&self) -> Vec<Entry> {
        let Ok(file) = std::fs::File::open(&self.path) else {
            return Vec::new();
        };
        std::io::BufReader::new(file)
            .lines()
            .map_while(Result::ok)
            .filter_map(|l| serde_json::from_str(&l).ok())
            .collect()
    }

    /// Most recent successfully delivered text.
    pub fn last_text(&self) -> Option<String> {
        self.load()
            .into_iter()
            .rev()
            .find(|e| e.status == Status::Completed && !e.final_text().is_empty())
            .map(|e| e.final_text().to_string())
    }

    /// Saves a recording next to the history and returns its path.
    ///
    /// # Errors
    /// Returns an I/O error when the file cannot be written.
    pub fn save_audio(&self, entry_id: &str, wav: &[u8]) -> std::io::Result<PathBuf> {
        std::fs::create_dir_all(&self.recordings)?;
        let path = self.recordings.join(format!("{entry_id}.wav"));
        std::fs::write(&path, wav)?;
        Ok(path)
    }

    /// Drops the oldest entries (and their audio files) beyond `max_entries`;
    /// `0` keeps everything.
    ///
    /// # Errors
    /// Returns an I/O error when the log cannot be rewritten.
    pub fn trim(&self, max_entries: usize) -> std::io::Result<()> {
        let entries = self.load();
        if max_entries == 0 || entries.len() <= max_entries {
            return Ok(());
        }
        let (old, keep) = entries.split_at(entries.len() - max_entries);
        for audio in old.iter().filter_map(|e| e.audio_file.as_ref()) {
            let _ = std::fs::remove_file(audio);
        }
        let tmp = self.path.with_extension("jsonl.tmp");
        {
            let mut f = std::fs::File::create(&tmp)?;
            for e in keep {
                writeln!(f, "{}", serde_json::to_string(e).map_err(std::io::Error::other)?)?;
            }
        }
        std::fs::rename(tmp, &self.path)
    }

    /// Persists a finished run according to the user's history settings:
    /// optionally keeps the recording as WAV, appends the entry and trims the log.
    ///
    /// # Errors
    /// Returns an I/O error when the entry cannot be written.
    pub fn record(&self, settings: &HistorySettings, mut entry: Entry, samples: &[f32]) -> std::io::Result<()> {
        if !settings.enabled {
            return Ok(());
        }
        if settings.save_audio && !samples.is_empty() {
            let wav = encode_wav_i16(samples, TARGET_SAMPLE_RATE);
            match self.save_audio(&entry.id, &wav) {
                Ok(path) => entry.audio_file = Some(path),
                Err(e) => log::warn!("could not save the recording: {e}"),
            }
        }
        self.append(&entry)?;
        self.trim(settings.max_entries)
    }

    /// Writes the whole history as CSV to `out`.
    ///
    /// # Errors
    /// Returns an I/O error when the file cannot be written.
    pub fn export_csv_file(&self, out: &Path) -> std::io::Result<usize> {
        let entries = self.load();
        let mut file = std::io::BufWriter::new(std::fs::File::create(out)?);
        export_csv(&entries, &mut file)?;
        file.flush()?;
        Ok(entries.len())
    }

    /// Deletes the whole history and all saved recordings.
    ///
    /// # Errors
    /// Returns an I/O error other than "not found".
    pub fn clear(&self) -> std::io::Result<()> {
        let ignore_missing = |r: std::io::Result<()>| match r {
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
            other => other,
        };
        ignore_missing(std::fs::remove_file(&self.path))?;
        ignore_missing(std::fs::remove_dir_all(&self.recordings))
    }
}

/// Writes history as CSV (like the macOS "Export" action).
///
/// # Errors
/// Returns any error from `out`.
pub fn export_csv(entries: &[Entry], out: &mut impl Write) -> std::io::Result<()> {
    fn esc(s: &str) -> String {
        format!("\"{}\"", s.replace('"', "\"\""))
    }
    writeln!(out, "timestamp,status,duration_s,mode,app,model,text,enhanced_text")?;
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

    fn temp_store() -> (PathBuf, HistoryStore) {
        let dir = std::env::temp_dir().join(format!("voiceink-hist-{}", uuid::Uuid::new_v4()));
        let store = HistoryStore::new(dir.join("history.jsonl"), dir.join("recordings"));
        (dir, store)
    }

    #[test]
    fn append_load_trim_and_clear() {
        let (dir, store) = temp_store();
        for i in 0..5 {
            let mut e = Entry::new(Status::Completed);
            e.text = format!("t{i}");
            if i == 0 {
                e.audio_file = Some(store.save_audio(&e.id, b"RIFF").unwrap());
            }
            store.append(&e).unwrap();
        }
        let mut failed = Entry::new(Status::Failed);
        failed.text = "Transcription Failed".into();
        store.append(&failed).unwrap();

        assert_eq!(store.load().len(), 6);
        assert_eq!(store.last_text().as_deref(), Some("t4"));
        let first_audio = store.load()[0].audio_file.clone().unwrap();
        store.trim(3).unwrap();
        let left = store.load();
        assert_eq!(left.len(), 3);
        assert_eq!(left[0].text, "t3");
        assert!(!first_audio.exists(), "trimmed entries lose their audio");

        let mut csv = Vec::new();
        export_csv(&left, &mut csv).unwrap();
        assert_eq!(String::from_utf8(csv).unwrap().lines().count(), 4);

        store.clear().unwrap();
        assert_eq!(store.load(), vec![]);
        store.clear().unwrap();
        std::fs::remove_dir_all(dir).ok();
    }

    #[test]
    fn record_follows_history_settings() {
        let (dir, store) = temp_store();
        let mut settings = HistorySettings { enabled: false, save_audio: true, max_entries: 2 };
        store.record(&settings, Entry::new(Status::Completed), &[0.0; 160]).unwrap();
        assert!(store.load().is_empty(), "disabled history writes nothing");

        settings.enabled = true;
        for _ in 0..3 {
            store.record(&settings, Entry::new(Status::Completed), &[0.0; 160]).unwrap();
        }
        let entries = store.load();
        assert_eq!(entries.len(), 2, "trimmed to max_entries");
        assert!(entries.iter().all(|e| e.audio_file.as_ref().is_some_and(|p| p.exists())));
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
