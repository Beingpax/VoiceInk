//! Keyboard / mouse shortcut handling that does not depend on Win32:
//! hotkey parsing, the press/release state machine and the recording policy.
//! `platform::hotkey` only installs the hooks and forwards raw events here.

pub mod controller;
pub mod hotkey;
pub mod trigger;

pub use controller::{Decision, Phase, RecordingPolicy};
pub use hotkey::{Hotkey, HotkeyError, Modifiers, is_modifier_vk, vk};
pub use trigger::{HotkeyEvent, ShortcutSet, TriggerKind};
