//! "Start with Windows" via `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`.

use windows::core::PCWSTR;
use windows::Win32::System::Registry::{
    RegCloseKey, RegDeleteValueW, RegOpenKeyExW, RegQueryValueExW, RegSetValueExW, HKEY,
    HKEY_CURRENT_USER, KEY_READ, KEY_WRITE, REG_SZ,
};

const RUN_KEY: &str = r"Software\Microsoft\Windows\CurrentVersion\Run";
const VALUE: &str = "VoiceInk";

fn open(access: windows::Win32::System::Registry::REG_SAM_FLAGS) -> Result<HKEY, String> {
    let path = super::wide(RUN_KEY);
    let mut key = HKEY::default();
    unsafe {
        RegOpenKeyExW(
            HKEY_CURRENT_USER,
            PCWSTR(path.as_ptr()),
            None,
            access,
            &mut key,
        )
    }
    .ok()
    .map_err(|e| e.to_string())?;
    Ok(key)
}

pub fn is_enabled() -> bool {
    let Ok(key) = open(KEY_READ) else {
        return false;
    };
    let name = super::wide(VALUE);
    let found =
        unsafe { RegQueryValueExW(key, PCWSTR(name.as_ptr()), None, None, None, None) }.is_ok();
    unsafe {
        let _ = RegCloseKey(key);
    }
    found
}

pub fn set_enabled(enabled: bool) -> Result<(), String> {
    let key = open(KEY_WRITE)?;
    let name = super::wide(VALUE);
    let result = unsafe {
        if enabled {
            let exe = std::env::current_exe().map_err(|e| e.to_string())?;
            let command = format!("\"{}\"", exe.display());
            let data: Vec<u8> = super::wide(&command)
                .iter()
                .flat_map(|u| u.to_le_bytes())
                .collect();
            RegSetValueExW(key, PCWSTR(name.as_ptr()), None, REG_SZ, Some(&data)).ok()
        } else {
            match RegDeleteValueW(key, PCWSTR(name.as_ptr())).ok() {
                Err(e) if e.code().0 as u32 == 0x8007_0002 => Ok(()), // not found
                other => other,
            }
        }
    };
    unsafe {
        let _ = RegCloseKey(key);
    }
    result.map_err(|e| e.to_string())
}
