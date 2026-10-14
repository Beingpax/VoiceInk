//! VoiceInk for Windows.
//!
//! The crate is split into a portable core (prompt building, text clean-up,
//! cloud providers, the transcription pipeline) that compiles and is unit
//! tested on any OS, and a `platform` layer that talks to Win32 through the
//! `windows` crate (WASAPI capture, global hotkey hook, tray icon, recorder
//! overlay, clipboard + `SendInput` paste, DPAPI credential storage).

pub mod audio;
pub mod config;
pub mod credentials;
pub mod enhancement;
pub mod history;
pub mod http;
pub mod modes;
pub mod pipeline;
pub mod prompts;
pub mod stats;
pub mod text;
pub mod transcription;

#[cfg(windows)]
pub mod platform;

pub const APP_NAME: &str = "VoiceInk";
pub const APP_VERSION: &str = env!("CARGO_PKG_VERSION");
