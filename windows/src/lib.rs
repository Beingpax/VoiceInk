//! `VoiceInk` for Windows.
//!
//! The crate is split into a portable core that compiles and is unit tested
//! on any OS, and a `platform` layer that talks to Win32 through the
//! `windows` crate:
//!
//! * **Domain & policy** — [`config`], [`prompts`], [`text`], [`modes`],
//!   [`input`] (shortcut state machines), [`stats`], [`settings_page`].
//! * **Use case** — [`pipeline`], which depends on providers only through the
//!   [`pipeline::Services`] trait.
//! * **Adapters** — [`transcription`], [`enhancement`], [`credentials`],
//!   [`history`], [`http`], [`audio`].
//! * **UI / OS** — `platform` (Windows only): capture, hooks, tray, windows.

pub mod artwork;
pub mod audio;
pub mod config;
pub mod context;
pub mod credentials;
pub mod enhancement;
pub mod history;
pub mod http;
pub mod input;
pub mod modes;
pub mod paths;
pub mod pipeline;
pub mod prompts;
pub mod settings_page;
pub mod stats;
pub mod text;
pub mod transcription;
pub mod ui;

#[cfg(windows)]
pub mod platform;

pub const APP_NAME: &str = "VoiceInk";
pub const APP_VERSION: &str = env!("CARGO_PKG_VERSION");
