//! "Start with Windows" via `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`.

use super::error::{Context, Error, Result};
use super::wide;
use windows::Win32::Foundation::ERROR_FILE_NOT_FOUND;
use windows::Win32::System::Registry::{
    HKEY, HKEY_CURRENT_USER, KEY_READ, KEY_WRITE, REG_SAM_FLAGS, REG_SZ, RegCloseKey, RegDeleteValueW, RegOpenKeyExW,
    RegQueryValueExW, RegSetValueExW,
};
use windows::core::{HRESULT, PCWSTR};

const RUN_KEY: &str = r"Software\Microsoft\Windows\CurrentVersion\Run";
const VALUE_NAME: &str = "VoiceInk";

/// An open registry key, closed on drop.
struct RegKey(HKEY);

impl RegKey {
    fn open_run_key(access: REG_SAM_FLAGS) -> Result<Self> {
        let path = wide(RUN_KEY);
        let mut key = HKEY::default();
        // SAFETY: `path` is NUL-terminated and `key` is a valid out-parameter.
        unsafe { RegOpenKeyExW(HKEY_CURRENT_USER, PCWSTR(path.as_ptr()), None, access, &raw mut key) }
            .ok()
            .context("open the Run registry key")?;
        Ok(Self(key))
    }
}

impl Drop for RegKey {
    fn drop(&mut self) {
        // SAFETY: the key was opened by RegOpenKeyExW and is closed exactly once.
        let _ = unsafe { RegCloseKey(self.0) };
    }
}

pub fn is_enabled() -> bool {
    let Ok(key) = RegKey::open_run_key(KEY_READ) else { return false };
    let name = wide(VALUE_NAME);
    // SAFETY: `name` is NUL-terminated; no output buffers are requested.
    unsafe { RegQueryValueExW(key.0, PCWSTR(name.as_ptr()), None, None, None, None) }.is_ok()
}

/// Adds or removes the autostart entry for the running executable.
///
/// # Errors
/// Fails when the registry cannot be written.
pub fn set_enabled(enabled: bool) -> Result<()> {
    let key = RegKey::open_run_key(KEY_WRITE)?;
    let name = wide(VALUE_NAME);
    if enabled {
        let exe = std::env::current_exe().map_err(|e| Error::Message(e.to_string()))?;
        let data: Vec<u8> =
            wide(&format!("\"{}\"", exe.display())).iter().flat_map(|unit| unit.to_le_bytes()).collect();
        // SAFETY: `name` is NUL-terminated and `data` is a NUL-terminated UTF-16 string.
        unsafe { RegSetValueExW(key.0, PCWSTR(name.as_ptr()), None, REG_SZ, Some(&data)) }
            .ok()
            .context("write the autostart entry")
    } else {
        // SAFETY: `name` is NUL-terminated.
        match unsafe { RegDeleteValueW(key.0, PCWSTR(name.as_ptr())) }.ok() {
            Err(e) if e.code() == HRESULT::from_win32(ERROR_FILE_NOT_FOUND.0) => Ok(()),
            other => other.context("remove the autostart entry"),
        }
    }
}
