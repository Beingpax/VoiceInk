//! COM initialization and audio-device helpers shared by capture and volume.

use super::error::{Context, Result};
use windows::Win32::Devices::FunctionDiscovery::PKEY_Device_FriendlyName;
use windows::Win32::Foundation::RPC_E_CHANGED_MODE;
use windows::Win32::Media::Audio::{IMMDevice, IMMDeviceEnumerator, MMDeviceEnumerator};
use windows::Win32::System::Com::StructuredStorage::PropVariantToStringAlloc;
use windows::Win32::System::Com::{
    CLSCTX_ALL, COINIT, COINIT_APARTMENTTHREADED, COINIT_MULTITHREADED, CoCreateInstance, CoInitializeEx,
    CoTaskMemFree, CoUninitialize, STGM_READ,
};

/// Initializes COM for the current thread and balances it on drop. A thread
/// that already uses another apartment model (the STA UI thread) keeps it.
pub struct ComGuard {
    owned: bool,
}

impl ComGuard {
    /// Joins the multithreaded apartment (worker threads).
    ///
    /// # Errors
    /// Fails when COM cannot be initialized.
    pub fn new() -> Result<Self> {
        Self::init(COINIT_MULTITHREADED)
    }

    /// Creates a single-threaded apartment (the UI thread; the shell needs it).
    ///
    /// # Errors
    /// Fails when COM cannot be initialized.
    pub fn apartment_threaded() -> Result<Self> {
        Self::init(COINIT_APARTMENTTHREADED)
    }

    fn init(model: COINIT) -> Result<Self> {
        // SAFETY: no reserved parameter; balanced by CoUninitialize in Drop.
        let hr = unsafe { CoInitializeEx(None, model) };
        if hr == RPC_E_CHANGED_MODE {
            return Ok(Self { owned: false });
        }
        hr.ok().context("COM initialization")?;
        Ok(Self { owned: true })
    }
}

impl Drop for ComGuard {
    fn drop(&mut self) {
        if self.owned {
            // SAFETY: matches the successful CoInitializeEx in `new`.
            unsafe { CoUninitialize() };
        }
    }
}

/// # Errors
/// Fails when the `MMDevice` API is unavailable.
pub fn device_enumerator() -> Result<IMMDeviceEnumerator> {
    // SAFETY: standard COM activation of a system class; COM is initialized by the caller.
    unsafe { CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL) }.context("audio device enumerator")
}

/// The device's display name, e.g. "Microphone (USB Audio)".
pub fn friendly_name(device: &IMMDevice) -> Option<String> {
    // SAFETY: COM calls on a valid device; the string returned by
    // PropVariantToStringAlloc is copied and then freed with CoTaskMemFree.
    unsafe {
        let store = device.OpenPropertyStore(STGM_READ).ok()?;
        let value = store.GetValue(&PKEY_Device_FriendlyName).ok()?;
        let pwstr = PropVariantToStringAlloc(&raw const value).ok()?;
        let name = pwstr.to_string().ok();
        CoTaskMemFree(Some(pwstr.0.cast_const().cast()));
        name
    }
}
