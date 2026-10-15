//! Mutes system output while recording (macOS `MediaController` behaviour).

use super::com::device_enumerator;
use windows::Win32::Media::Audio::Endpoints::IAudioEndpointVolume;
use windows::Win32::Media::Audio::{eConsole, eRender};
use windows::Win32::System::Com::CLSCTX_ALL;

fn endpoint_volume() -> Option<IAudioEndpointVolume> {
    let enumerator = device_enumerator().ok()?;
    // SAFETY: COM calls on a valid enumerator; COM is initialized on the UI thread.
    unsafe { enumerator.GetDefaultAudioEndpoint(eRender, eConsole).ok()?.Activate(CLSCTX_ALL, None).ok() }
}

/// Mutes the default output device. Returns a guard that unmutes on drop,
/// or `None` when output was already muted or is unavailable.
pub fn mute_output() -> Option<MuteGuard> {
    let volume = endpoint_volume()?;
    // SAFETY: COM calls on a valid endpoint; a null event-context GUID is allowed.
    unsafe {
        if volume.GetMute().ok()?.as_bool() {
            return None;
        }
        volume.SetMute(true, std::ptr::null()).ok()?;
    }
    Some(MuteGuard)
}

/// Unmutes on drop. Holds no COM pointer so it can move between threads.
pub struct MuteGuard;

impl Drop for MuteGuard {
    fn drop(&mut self) {
        if let Some(volume) = endpoint_volume() {
            // SAFETY: as in `mute_output`.
            let _ = unsafe { volume.SetMute(false, std::ptr::null()) };
        }
    }
}
