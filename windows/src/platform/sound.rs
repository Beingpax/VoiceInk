//! Start/stop feedback sounds (`SoundManager`), played asynchronously.

use super::wide;
use std::path::Path;
use windows::Win32::Media::Audio::{PlaySoundW, SND_ASYNC, SND_FILENAME, SND_MEMORY, SND_NODEFAULT};
use windows::core::PCWSTR;

static START_WAV: &[u8] = include_bytes!("../../../VoiceInk/Resources/Sounds/sound1.wav");
static STOP_WAV: &[u8] = include_bytes!("../../../VoiceInk/Resources/Sounds/sound3.wav");
static CANCEL_WAV: &[u8] = include_bytes!("../../../VoiceInk/Resources/Sounds/sound7.wav");

#[derive(Debug, Clone, Copy)]
pub enum Cue {
    Start,
    Stop,
    Cancel,
}

impl Cue {
    fn builtin(self) -> &'static [u8] {
        match self {
            Cue::Start => START_WAV,
            Cue::Stop => STOP_WAV,
            Cue::Cancel => CANCEL_WAV,
        }
    }
}

/// Plays `custom` (a WAV file) if it exists, else the built-in sound for `cue`.
pub fn play(cue: Cue, custom: Option<&Path>) {
    if let Some(path) = custom.filter(|p| p.exists()) {
        let path = wide(&path.to_string_lossy());
        // SAFETY: `path` is NUL-terminated; SND_ASYNC copies what it needs.
        let _ = unsafe { PlaySoundW(PCWSTR(path.as_ptr()), None, SND_FILENAME | SND_ASYNC | SND_NODEFAULT) };
        return;
    }
    // SAFETY: with SND_MEMORY the pointer is read as a WAV image (not as text);
    // the data is 'static, so it outlives the asynchronous playback.
    let _ = unsafe { PlaySoundW(PCWSTR(cue.builtin().as_ptr().cast()), None, SND_MEMORY | SND_ASYNC | SND_NODEFAULT) };
}
