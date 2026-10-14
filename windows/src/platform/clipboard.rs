//! Clipboard access (the `ClipboardManager` / `NSPasteboard` counterpart).
//!
//! Text placed for pasting is marked so Windows clipboard history (Win+V) and
//! cloud clipboard skip it, mirroring the macOS "transient" pasteboard type.
//! The previous clipboard can be snapshotted (all memory-backed formats,
//! including images as `CF_DIB`) and restored afterwards.

use std::time::{Duration, Instant};
use windows::core::PCWSTR;
use windows::Win32::Foundation::{GlobalFree, HANDLE, HGLOBAL};
use windows::Win32::System::DataExchange::{
    CloseClipboard, EmptyClipboard, EnumClipboardFormats, GetClipboardData,
    GetClipboardSequenceNumber, IsClipboardFormatAvailable, OpenClipboard,
    RegisterClipboardFormatW, SetClipboardData,
};
use windows::Win32::System::Memory::{
    GlobalAlloc, GlobalLock, GlobalSize, GlobalUnlock, GMEM_MOVEABLE,
};

const CF_UNICODETEXT: u32 = 13;
/// Formats whose handles are GDI objects rather than `HGLOBAL`s.
const NON_GLOBAL_FORMATS: &[u32] = &[2, 3, 9, 14, 0x80, 0x82, 0x83, 0x8E];

/// RAII wrapper around `OpenClipboard`/`CloseClipboard` with retries
/// (another process may hold the clipboard briefly).
struct Open;

impl Open {
    fn new() -> Result<Self, String> {
        let deadline = Instant::now() + Duration::from_millis(500);
        loop {
            if unsafe { OpenClipboard(None) }.is_ok() {
                return Ok(Open);
            }
            if Instant::now() > deadline {
                return Err("the clipboard is in use by another application".into());
            }
            std::thread::sleep(Duration::from_millis(15));
        }
    }
}

impl Drop for Open {
    fn drop(&mut self) {
        unsafe {
            let _ = CloseClipboard();
        }
    }
}

fn register(name: &str) -> u32 {
    let w = super::wide(name);
    unsafe { RegisterClipboardFormatW(PCWSTR(w.as_ptr())) }
}

unsafe fn global_from_bytes(bytes: &[u8]) -> Result<HGLOBAL, String> {
    let h = GlobalAlloc(GMEM_MOVEABLE, bytes.len().max(1)).map_err(|e| e.to_string())?;
    let ptr = GlobalLock(h) as *mut u8;
    if ptr.is_null() {
        let _ = GlobalFree(Some(h));
        return Err("GlobalLock failed".into());
    }
    std::ptr::copy_nonoverlapping(bytes.as_ptr(), ptr, bytes.len());
    let _ = GlobalUnlock(h);
    Ok(h)
}

unsafe fn set_bytes(format: u32, bytes: &[u8]) -> Result<(), String> {
    let h = global_from_bytes(bytes)?;
    if let Err(e) = SetClipboardData(format, Some(HANDLE(h.0))) {
        let _ = GlobalFree(Some(h));
        return Err(format!("SetClipboardData failed: {e}"));
    }
    Ok(())
}

unsafe fn read_bytes(format: u32) -> Option<Vec<u8>> {
    let handle = GetClipboardData(format).ok()?;
    let h = HGLOBAL(handle.0);
    let size = GlobalSize(h);
    let ptr = GlobalLock(h) as *const u8;
    if ptr.is_null() {
        return None;
    }
    let data = std::slice::from_raw_parts(ptr, size).to_vec();
    let _ = GlobalUnlock(h);
    Some(data)
}

/// Reads the clipboard as text, if it holds any.
pub fn get_text() -> Option<String> {
    unsafe {
        if IsClipboardFormatAvailable(CF_UNICODETEXT).is_err() {
            return None;
        }
        let _open = Open::new().ok()?;
        let bytes = read_bytes(CF_UNICODETEXT)?;
        let units: Vec<u16> = bytes
            .chunks_exact(2)
            .map(|c| u16::from_le_bytes([c[0], c[1]]))
            .take_while(|&u| u != 0)
            .collect();
        Some(String::from_utf16_lossy(&units))
    }
}

/// Replaces the clipboard with `text`. With `transient`, the entry is kept out
/// of clipboard history and cloud sync. Returns the new sequence number.
pub fn set_text(text: &str, transient: bool) -> Result<u32, String> {
    unsafe {
        let _open = Open::new()?;
        EmptyClipboard().map_err(|e| e.to_string())?;
        let mut bytes: Vec<u8> = Vec::with_capacity(text.len() * 2 + 2);
        for unit in text.encode_utf16().chain(std::iter::once(0)) {
            bytes.extend_from_slice(&unit.to_le_bytes());
        }
        set_bytes(CF_UNICODETEXT, &bytes)?;
        if transient {
            let zero = 0u32.to_le_bytes();
            let _ = set_bytes(
                register("ExcludeClipboardContentFromMonitorProcessing"),
                &zero,
            );
            let _ = set_bytes(register("CanIncludeInClipboardHistory"), &zero);
            let _ = set_bytes(register("CanUploadToCloudClipboard"), &zero);
        }
    }
    Ok(sequence_number())
}

pub fn sequence_number() -> u32 {
    unsafe { GetClipboardSequenceNumber() }
}

/// All memory-backed clipboard formats, for restoring after a paste.
#[derive(Debug, Default)]
pub struct Snapshot {
    items: Vec<(u32, Vec<u8>)>,
}

impl Snapshot {
    pub fn capture() -> Snapshot {
        let mut items = Vec::new();
        unsafe {
            let Ok(_open) = Open::new() else {
                return Snapshot { items };
            };
            let mut format = 0u32;
            loop {
                format = EnumClipboardFormats(format);
                if format == 0 {
                    break;
                }
                if NON_GLOBAL_FORMATS.contains(&format) {
                    continue;
                }
                if let Some(bytes) = read_bytes(format) {
                    items.push((format, bytes));
                }
            }
        }
        Snapshot { items }
    }

    pub fn restore(&self) -> Result<(), String> {
        unsafe {
            let _open = Open::new()?;
            EmptyClipboard().map_err(|e| e.to_string())?;
            for (format, bytes) in &self.items {
                // Synthesized formats (e.g. CF_TEXT from CF_UNICODETEXT) may fail; that's fine.
                let _ = set_bytes(*format, bytes);
            }
        }
        Ok(())
    }
}
