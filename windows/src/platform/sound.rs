//! Start/stop feedback sounds (`SoundManager`), played asynchronously.

use std::path::Path;
use windows::core::PCWSTR;
use windows::Win32::Media::Audio::{
    PlaySoundW, SND_ASYNC, SND_FILENAME, SND_MEMORY, SND_NODEFAULT,
};

static START_WAV: &[u8] = include_bytes!("../../../VoiceInk/Resources/Sounds/sound1.wav");
static STOP_WAV: &[u8] = include_bytes!("../../../VoiceInk/Resources/Sounds/sound3.wav");
static CANCEL_WAV: &[u8] = include_bytes!("../../../VoiceInk/Resources/Sounds/sound7.wav");

#[derive(Debug, Clone, Copy)]
pub enum Cue {
    Start,
    Stop,
    Cancel,
}

pub fn play(cue: Cue, custom: Option<&Path>) {
    unsafe {
        if let Some(path) = custom.filter(|p| p.exists()) {
            let w = super::wide(&path.to_string_lossy());
            let _ = PlaySoundW(
                PCWSTR(w.as_ptr()),
                None,
                SND_FILENAME | SND_ASYNC | SND_NODEFAULT,
            );
            return;
        }
        let data = match cue {
            Cue::Start => START_WAV,
            Cue::Stop => STOP_WAV,
            Cue::Cancel => CANCEL_WAV,
        };
        // SND_MEMORY reads the WAV image directly; the statics live for the whole program.
        let _ = PlaySoundW(
            PCWSTR(data.as_ptr() as *const u16),
            None,
            SND_MEMORY | SND_ASYNC | SND_NODEFAULT,
        );
    }
}
