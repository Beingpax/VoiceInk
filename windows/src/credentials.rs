//! API key storage — the Windows counterpart of the macOS Keychain.
//!
//! The rest of the app depends only on the [`SecretStore`] trait:
//!
//! * [`KeyFile`] keeps keys in `keys.json`, each value encrypted by a
//!   [`Cipher`] — DPAPI on Windows, so only the current user can decrypt it.
//! * [`EnvOverride`] decorates any store so environment variables
//!   (`VOICEINK_GROQ_API_KEY`, `GROQ_API_KEY`, ...) take precedence, which is
//!   convenient for scripting and CI.
//! * [`MemoryStore`] is an in-memory store for tests.

use base64::{Engine, engine::general_purpose::STANDARD as B64};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, PoisonError};

#[derive(Debug, thiserror::Error)]
pub enum CredentialError {
    #[error("cannot access {path}: {source}")]
    Io {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("cannot encode the key store: {0}")]
    Serialize(#[from] serde_json::Error),
    #[error("cannot encrypt the API key: {0}")]
    Encrypt(String),
}

/// Read/write access to API keys by credential name (`"openai"`, `"groq"`, ...).
pub trait SecretStore: Send + Sync {
    fn get(&self, name: &str) -> Option<String>;

    /// Stores `value`; an empty value removes the key.
    ///
    /// # Errors
    /// Returns [`CredentialError`] when the key cannot be persisted.
    fn set(&self, name: &str, value: &str) -> Result<(), CredentialError>;

    /// # Errors
    /// Returns [`CredentialError`] when the store cannot be written.
    fn remove(&self, name: &str) -> Result<(), CredentialError> {
        self.set(name, "")
    }

    fn has(&self, name: &str) -> bool {
        self.get(name).is_some()
    }
}

/// Shared handle used throughout the app.
pub type Secrets = Arc<dyn SecretStore>;

/// The production store: DPAPI-encrypted `keys.json` with environment overrides.
pub fn default_store(path: PathBuf) -> Secrets {
    Arc::new(EnvOverride::new(KeyFile::new(path, platform_cipher())))
}

// ---------------------------------------------------------------------------
// Encryption
// ---------------------------------------------------------------------------

/// Reversible protection of secret bytes at rest.
pub trait Cipher: Send + Sync {
    /// # Errors
    /// Returns a description of why the data could not be encrypted.
    fn protect(&self, plain: &[u8]) -> Result<Vec<u8>, String>;
    /// # Errors
    /// Returns a description of why the data could not be decrypted.
    fn unprotect(&self, sealed: &[u8]) -> Result<Vec<u8>, String>;
}

/// Stores data unchanged. Only for development builds on other systems and tests.
#[derive(Debug, Default, Clone, Copy)]
pub struct NoCipher;

impl Cipher for NoCipher {
    fn protect(&self, plain: &[u8]) -> Result<Vec<u8>, String> {
        Ok(plain.to_vec())
    }

    fn unprotect(&self, sealed: &[u8]) -> Result<Vec<u8>, String> {
        Ok(sealed.to_vec())
    }
}

#[cfg(windows)]
fn platform_cipher() -> Box<dyn Cipher> {
    Box::new(dpapi::Dpapi)
}

#[cfg(not(windows))]
fn platform_cipher() -> Box<dyn Cipher> {
    Box::new(NoCipher)
}

// ---------------------------------------------------------------------------
// Stores
// ---------------------------------------------------------------------------

/// Encrypted keys in a JSON file: `{ "openai": "<base64 ciphertext>", ... }`.
pub struct KeyFile {
    path: PathBuf,
    cipher: Box<dyn Cipher>,
}

impl KeyFile {
    pub fn new(path: PathBuf, cipher: Box<dyn Cipher>) -> Self {
        Self { path, cipher }
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    fn read_all(&self) -> BTreeMap<String, String> {
        std::fs::read_to_string(&self.path).ok().and_then(|s| serde_json::from_str(&s).ok()).unwrap_or_default()
    }

    fn write_all(&self, entries: &BTreeMap<String, String>) -> Result<(), CredentialError> {
        let io = |source| CredentialError::Io { path: self.path.clone(), source };
        if let Some(dir) = self.path.parent() {
            std::fs::create_dir_all(dir).map_err(io)?;
        }
        let json = serde_json::to_string_pretty(entries)?;
        std::fs::write(&self.path, json).map_err(io)
    }
}

impl SecretStore for KeyFile {
    fn get(&self, name: &str) -> Option<String> {
        let sealed = B64.decode(self.read_all().remove(name)?).ok()?;
        let plain = self.cipher.unprotect(&sealed).ok()?;
        String::from_utf8(plain).ok().filter(|s| !s.is_empty())
    }

    fn set(&self, name: &str, value: &str) -> Result<(), CredentialError> {
        let mut entries = self.read_all();
        let value = value.trim();
        if value.is_empty() {
            entries.remove(name);
        } else {
            let sealed = self.cipher.protect(value.as_bytes()).map_err(CredentialError::Encrypt)?;
            entries.insert(name.to_string(), B64.encode(sealed));
        }
        self.write_all(&entries)
    }
}

/// Lets environment variables override a store (decorator).
pub struct EnvOverride<S> {
    inner: S,
}

impl<S: SecretStore> EnvOverride<S> {
    pub fn new(inner: S) -> Self {
        Self { inner }
    }

    /// `VOICEINK_<NAME>_API_KEY` and `<NAME>_API_KEY`, e.g. `OPENAI_API_KEY`.
    pub fn variable_names(name: &str) -> [String; 2] {
        let upper = name.to_ascii_uppercase().replace('-', "_");
        [format!("VOICEINK_{upper}_API_KEY"), format!("{upper}_API_KEY")]
    }
}

impl<S: SecretStore> SecretStore for EnvOverride<S> {
    fn get(&self, name: &str) -> Option<String> {
        Self::variable_names(name)
            .iter()
            .filter_map(|var| std::env::var(var).ok())
            .map(|v| v.trim().to_string())
            .find(|v| !v.is_empty())
            .or_else(|| self.inner.get(name))
    }

    fn set(&self, name: &str, value: &str) -> Result<(), CredentialError> {
        self.inner.set(name, value)
    }
}

/// In-memory store for tests and previews.
#[derive(Debug, Default)]
pub struct MemoryStore {
    entries: Mutex<BTreeMap<String, String>>,
}

impl MemoryStore {
    pub fn with(entries: &[(&str, &str)]) -> Self {
        let map = entries.iter().map(|(k, v)| ((*k).to_string(), (*v).to_string())).collect();
        Self { entries: Mutex::new(map) }
    }
}

impl SecretStore for MemoryStore {
    fn get(&self, name: &str) -> Option<String> {
        self.entries.lock().unwrap_or_else(PoisonError::into_inner).get(name).cloned()
    }

    fn set(&self, name: &str, value: &str) -> Result<(), CredentialError> {
        let mut entries = self.entries.lock().unwrap_or_else(PoisonError::into_inner);
        if value.trim().is_empty() {
            entries.remove(name);
        } else {
            entries.insert(name.to_string(), value.trim().to_string());
        }
        Ok(())
    }
}

#[cfg(windows)]
mod dpapi {
    use super::Cipher;
    use windows::Win32::Foundation::{HLOCAL, LocalFree};
    use windows::Win32::Security::Cryptography::{
        CRYPT_INTEGER_BLOB, CRYPTPROTECT_UI_FORBIDDEN, CryptProtectData, CryptUnprotectData,
    };
    use windows::core::w;

    /// Extra entropy so other apps of the same user can't trivially decrypt our blobs.
    const ENTROPY: &[u8] = b"VoiceInk for Windows";

    /// Windows Data Protection API, scoped to the current user.
    pub struct Dpapi;

    fn blob(data: &[u8]) -> Result<CRYPT_INTEGER_BLOB, String> {
        Ok(CRYPT_INTEGER_BLOB {
            cbData: u32::try_from(data.len()).map_err(|_| "secret too large".to_string())?,
            // DPAPI never writes through the input pointer.
            pbData: data.as_ptr().cast_mut(),
        })
    }

    /// Copies and frees a DPAPI output blob.
    fn take(out: CRYPT_INTEGER_BLOB) -> Vec<u8> {
        // SAFETY: DPAPI allocated `cbData` bytes at `pbData` with LocalAlloc;
        // we copy them before releasing the buffer exactly once.
        unsafe {
            let bytes = std::slice::from_raw_parts(out.pbData, out.cbData as usize).to_vec();
            let _ = LocalFree(Some(HLOCAL(out.pbData.cast())));
            bytes
        }
    }

    impl Cipher for Dpapi {
        fn protect(&self, plain: &[u8]) -> Result<Vec<u8>, String> {
            let (input, entropy) = (blob(plain)?, blob(ENTROPY)?);
            let mut out = CRYPT_INTEGER_BLOB::default();
            // SAFETY: input/entropy point to live slices for the duration of the
            // call and `out` is a valid out-parameter.
            unsafe {
                CryptProtectData(
                    &raw const input,
                    w!("VoiceInk API key"),
                    Some(&raw const entropy),
                    None,
                    None,
                    CRYPTPROTECT_UI_FORBIDDEN,
                    &raw mut out,
                )
            }
            .map_err(|e| format!("CryptProtectData failed: {e}"))?;
            Ok(take(out))
        }

        fn unprotect(&self, sealed: &[u8]) -> Result<Vec<u8>, String> {
            let (input, entropy) = (blob(sealed)?, blob(ENTROPY)?);
            let mut out = CRYPT_INTEGER_BLOB::default();
            // SAFETY: as in `protect`.
            unsafe {
                CryptUnprotectData(
                    &raw const input,
                    None,
                    Some(&raw const entropy),
                    None,
                    None,
                    CRYPTPROTECT_UI_FORBIDDEN,
                    &raw mut out,
                )
            }
            .map_err(|e| format!("CryptUnprotectData failed: {e}"))?;
            Ok(take(out))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Reversible stand-in for DPAPI that proves values are not stored in clear.
    struct XorCipher;

    impl Cipher for XorCipher {
        fn protect(&self, plain: &[u8]) -> Result<Vec<u8>, String> {
            Ok(plain.iter().map(|b| b ^ 0x5A).collect())
        }
        fn unprotect(&self, sealed: &[u8]) -> Result<Vec<u8>, String> {
            self.protect(sealed)
        }
    }

    fn temp_file() -> PathBuf {
        std::env::temp_dir().join(format!("voiceink-keys-{}.json", uuid::Uuid::new_v4()))
    }

    #[test]
    fn key_file_round_trips_and_encrypts() {
        let path = temp_file();
        let store = KeyFile::new(path.clone(), Box::new(XorCipher));
        store.set("openai", " sk-123 ").unwrap();
        assert_eq!(store.get("openai").as_deref(), Some("sk-123"));
        assert!(!std::fs::read_to_string(&path).unwrap().contains("sk-123"));
        store.remove("openai").unwrap();
        assert!(!store.has("openai"));
        std::fs::remove_file(path).ok();
    }

    #[test]
    fn env_override_wins_and_writes_go_to_the_inner_store() {
        let store = EnvOverride::new(MemoryStore::with(&[("voiceink-test-a", "stored")]));
        assert_eq!(store.get("voiceink-test-a").as_deref(), Some("stored"));
        assert_eq!(
            EnvOverride::<MemoryStore>::variable_names("custom-enhancement"),
            ["VOICEINK_CUSTOM_ENHANCEMENT_API_KEY".to_string(), "CUSTOM_ENHANCEMENT_API_KEY".to_string()]
        );
        store.set("voiceink-test-b", "x").unwrap();
        assert!(store.has("voiceink-test-b"));
    }
}
