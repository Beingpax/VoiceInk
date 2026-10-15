//! Composition root: builds the long-lived services once and hands them to
//! the CLI and the Windows app (no global state).

use crate::config::{Config, ConfigError};
use crate::credentials::{self, Secrets};
use crate::history::HistoryStore;
use crate::paths::AppPaths;
use crate::pipeline::LiveServices;
use std::sync::Arc;

#[derive(Clone)]
pub struct AppContext {
    pub paths: AppPaths,
    pub secrets: Secrets,
    pub history: HistoryStore,
    pub services: Arc<LiveServices>,
}

impl AppContext {
    pub fn new(paths: AppPaths) -> Self {
        let secrets = credentials::default_store(paths.credentials());
        let history = HistoryStore::new(paths.history(), paths.recordings());
        let services = Arc::new(LiveServices::new(Arc::clone(&secrets), paths.models()));
        Self { paths, secrets, history, services }
    }

    /// Context for the real data directory (see [`AppPaths::detect`]).
    pub fn detect() -> Self {
        Self::new(AppPaths::detect())
    }

    /// Loads (or creates) the settings file.
    ///
    /// # Errors
    /// Returns [`ConfigError`] when the file is unreadable or invalid.
    pub fn load_config(&self) -> Result<Config, ConfigError> {
        Config::load(&self.paths.config())
    }
}
