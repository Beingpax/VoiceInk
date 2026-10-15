//! The settings file as seen by the running app: the parsed [`Config`] plus
//! the modification time used to pick up hand edits.

use crate::config::{Config, ConfigError};
use std::path::PathBuf;
use std::time::SystemTime;

pub struct ConfigFile {
    path: PathBuf,
    config: Config,
    modified: Option<SystemTime>,
}

impl ConfigFile {
    /// Loads (or creates) the file.
    ///
    /// # Errors
    /// Returns [`ConfigError`] when the file is unreadable or invalid.
    pub fn open(path: PathBuf) -> Result<Self, ConfigError> {
        let config = Config::load(&path)?;
        let modified = modified(&path);
        Ok(Self { path, config, modified })
    }

    pub fn get(&self) -> &Config {
        &self.config
    }

    /// Re-reads the file if it changed on disk (or always with `force`).
    /// Returns true when the configuration was replaced.
    ///
    /// # Errors
    /// Returns [`ConfigError`] when the changed file is invalid; the previous
    /// configuration stays in effect.
    pub fn reload(&mut self, force: bool) -> Result<bool, ConfigError> {
        let modified = modified(&self.path);
        if !force && modified == self.modified {
            return Ok(false);
        }
        self.config = Config::load(&self.path)?;
        self.modified = modified;
        Ok(true)
    }

    /// Changes the configuration and writes it.
    ///
    /// # Errors
    /// Returns [`ConfigError::Io`] when the file cannot be written; the change
    /// stays in effect for this session.
    pub fn update(&mut self, change: impl FnOnce(&mut Config)) -> Result<(), ConfigError> {
        change(&mut self.config);
        let saved = self.config.save(&self.path);
        self.modified = modified(&self.path);
        saved
    }
}

fn modified(path: &std::path::Path) -> Option<SystemTime> {
    std::fs::metadata(path).and_then(|m| m.modified()).ok()
}
