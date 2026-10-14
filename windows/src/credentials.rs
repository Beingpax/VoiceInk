//! API key storage — the Windows counterpart of the macOS Keychain.
//!
//! Keys live in `%APPDATA%\VoiceInk\keys.json`, each value encrypted with
//! DPAPI (`CryptProtectData`) so only the current Windows user can decrypt
//! it. Environment variables (`VOICEINK_GROQ_API_KEY`, `GROQ_API_KEY`, ...)
//! take precedence, which is convenient for scripting and CI.

use base64::{engine::general_purpose::STANDARD as B64, Engine};
use std::collections::BTreeMap;
use std::path::PathBuf;

pub fn store_path() -> PathBuf {
    crate::config::data_dir().join("keys.json")
}

fn env_names(name: &str) -> [String; 2] {
    let upper = name.to_ascii_uppercase().replace('-', "_");
    [
        format!("VOICEINK_{upper}_API_KEY"),
        format!("{upper}_API_KEY"),
    ]
}

fn load_store() -> BTreeMap<String, String> {
    std::fs::read_to_string(store_path())
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

fn save_store(store: &BTreeMap<String, String>) -> Result<(), String> {
    let path = store_path();
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    }
    let json = serde_json::to_string_pretty(store).map_err(|e| e.to_string())?;
    std::fs::write(path, json).map_err(|e| e.to_string())
}

/// Returns the API key for a provider key name (`"groq"`, `"openai"`, ...).
pub fn get(name: &str) -> Option<String> {
    if name.is_empty() {
        return None;
    }
    for var in env_names(name) {
        if let Ok(v) = std::env::var(&var) {
            if !v.trim().is_empty() {
                return Some(v.trim().to_string());
            }
        }
    }
    let encoded = load_store().remove(name)?;
    let bytes = B64.decode(encoded).ok()?;
    let plain = unprotect(&bytes).ok()?;
    String::from_utf8(plain).ok().filter(|s| !s.is_empty())
}

pub fn has(name: &str) -> bool {
    get(name).is_some()
}

pub fn set(name: &str, key: &str) -> Result<(), String> {
    let mut store = load_store();
    let key = key.trim();
    if key.is_empty() {
        store.remove(name);
    } else {
        store.insert(name.to_string(), B64.encode(protect(key.as_bytes())?));
    }
    save_store(&store)
}

pub fn remove(name: &str) -> Result<(), String> {
    set(name, "")
}

pub fn stored_names() -> Vec<String> {
    load_store().into_keys().collect()
}

#[cfg(windows)]
fn protect(data: &[u8]) -> Result<Vec<u8>, String> {
    dpapi::protect(data)
}

#[cfg(windows)]
fn unprotect(data: &[u8]) -> Result<Vec<u8>, String> {
    dpapi::unprotect(data)
}

// Non-Windows builds exist only for development and tests; keys are merely encoded.
#[cfg(not(windows))]
fn protect(data: &[u8]) -> Result<Vec<u8>, String> {
    Ok(data.to_vec())
}

#[cfg(not(windows))]
fn unprotect(data: &[u8]) -> Result<Vec<u8>, String> {
    Ok(data.to_vec())
}

#[cfg(windows)]
mod dpapi {
    use windows::core::w;
    use windows::Win32::Foundation::{LocalFree, HLOCAL};
    use windows::Win32::Security::Cryptography::{
        CryptProtectData, CryptUnprotectData, CRYPTPROTECT_UI_FORBIDDEN, CRYPT_INTEGER_BLOB,
    };

    const ENTROPY: &[u8] = b"VoiceInk for Windows";

    fn blob(data: &[u8]) -> CRYPT_INTEGER_BLOB {
        CRYPT_INTEGER_BLOB {
            cbData: data.len() as u32,
            pbData: data.as_ptr() as *mut u8,
        }
    }

    unsafe fn take(out: CRYPT_INTEGER_BLOB) -> Vec<u8> {
        let v = std::slice::from_raw_parts(out.pbData, out.cbData as usize).to_vec();
        let _ = LocalFree(Some(HLOCAL(out.pbData as *mut _)));
        v
    }

    pub fn protect(data: &[u8]) -> Result<Vec<u8>, String> {
        let input = blob(data);
        let entropy = blob(ENTROPY);
        let mut out = CRYPT_INTEGER_BLOB::default();
        unsafe {
            CryptProtectData(
                &input,
                w!("VoiceInk API key"),
                Some(&entropy),
                None,
                None,
                CRYPTPROTECT_UI_FORBIDDEN,
                &mut out,
            )
            .map_err(|e| format!("CryptProtectData failed: {e}"))?;
            Ok(take(out))
        }
    }

    pub fn unprotect(data: &[u8]) -> Result<Vec<u8>, String> {
        let input = blob(data);
        let entropy = blob(ENTROPY);
        let mut out = CRYPT_INTEGER_BLOB::default();
        unsafe {
            CryptUnprotectData(
                &input,
                None,
                Some(&entropy),
                None,
                None,
                CRYPTPROTECT_UI_FORBIDDEN,
                &mut out,
            )
            .map_err(|e| format!("CryptUnprotectData failed: {e}"))?;
            Ok(take(out))
        }
    }
}
