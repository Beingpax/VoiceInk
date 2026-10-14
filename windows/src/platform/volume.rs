//! Mutes system output while recording (macOS `MediaController` behaviour).

use windows::Win32::Media::Audio::Endpoints::IAudioEndpointVolume;
use windows::Win32::Media::Audio::{eConsole, eRender, IMMDeviceEnumerator, MMDeviceEnumerator};
use windows::Win32::System::Com::{CoCreateInstance, CLSCTX_ALL};

fn endpoint_volume() -> windows::core::Result<IAudioEndpointVolume> {
    unsafe {
        let enumerator: IMMDeviceEnumerator =
            CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL)?;
        let device = enumerator.GetDefaultAudioEndpoint(eRender, eConsole)?;
        device.Activate(CLSCTX_ALL, None)
    }
}

/// Mutes the default output device. Returns a guard that restores the
/// previous state, or `None` when it was already muted / unavailable.
pub fn mute_output() -> Option<MuteGuard> {
    let volume = endpoint_volume().ok()?;
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
        if let Ok(volume) = endpoint_volume() {
            unsafe {
                let _ = volume.SetMute(false, std::ptr::null());
            }
        }
    }
}
