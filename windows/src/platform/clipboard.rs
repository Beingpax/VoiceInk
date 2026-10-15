//! Clipboard access (the `ClipboardManager` / `NSPasteboard` counterpart).
//!
//! Text placed for pasting is marked so Windows clipboard history (Win+V) and
//! cloud clipboard skip it, mirroring the macOS "transient" pasteboard type.
//! The previous clipboard can be snapshotted (all memory-backed formats,
//! including images as `CF_DIB`) and restored afterwards.
//!
//! All data access goes through [`OpenClipboard`], so the clipboard is
//! provably open while it is read or written and always closed afterwards.

use super::error::{Context, Error, Result};
use super::wide;
use std::time::{Duration, Instant};
use windows::Win32::Foundation::{GlobalFree, HANDLE, HGLOBAL};
use windows::Win32::System::DataExchange::{
    CloseClipboard, EmptyClipboard, EnumClipboardFormats, GetClipboardData, GetClipboardSequenceNumber,
    IsClipboardFormatAvailable, OpenClipboard as Win32OpenClipboard, RegisterClipboardFormatW, SetClipboardData,
};
use windows::Win32::System::Memory::{GMEM_MOVEABLE, GlobalAlloc, GlobalLock, GlobalSize, GlobalUnlock};
use windows::core::PCWSTR;

const CF_UNICODETEXT: u32 = 13;
/// Formats whose handles are GDI objects rather than `HGLOBAL`s
/// (bitmap, metafile, palette, enhanced metafile and their display variants).
const NON_GLOBAL_FORMATS: [u32; 8] = [2, 3, 9, 14, 0x80, 0x82, 0x83, 0x8E];
/// Formats that keep an entry out of Win+V history and cloud sync.
const PRIVACY_FORMATS: [&str; 3] =
    ["ExcludeClipboardContentFromMonitorProcessing", "CanIncludeInClipboardHistory", "CanUploadToCloudClipboard"];
/// Another process may hold the clipboard briefly.
const OPEN_TIMEOUT: Duration = Duration::from_millis(500);
const OPEN_RETRY_INTERVAL: Duration = Duration::from_millis(15);

/// The clipboard, opened by this thread; closed on drop.
struct OpenClipboard(());

// The methods take `&self` as proof that the clipboard is open.
#[allow(clippy::unused_self)]
impl OpenClipboard {
    fn open() -> Result<Self> {
        let deadline = Instant::now() + OPEN_TIMEOUT;
        loop {
            // SAFETY: no owner window is required; balanced by CloseClipboard in Drop.
            if unsafe { Win32OpenClipboard(None) }.is_ok() {
                return Ok(Self(()));
            }
            if Instant::now() > deadline {
                return Err(Error::Message("the clipboard is in use by another application".into()));
            }
            std::thread::sleep(OPEN_RETRY_INTERVAL);
        }
    }

    fn empty(&self) -> Result<()> {
        // SAFETY: the clipboard is open (we hold `self`).
        unsafe { EmptyClipboard() }.context("empty the clipboard")
    }

    /// Copies `bytes` into a movable global block owned by the clipboard.
    fn set(&self, format: u32, bytes: &[u8]) -> Result<()> {
        // SAFETY: the clipboard is open. The block is allocated with room for
        // `bytes`, locked only while copying, and freed only if the clipboard
        // did not take ownership.
        unsafe {
            let block = GlobalAlloc(GMEM_MOVEABLE, bytes.len().max(1)).context("allocate clipboard memory")?;
            let target = GlobalLock(block).cast::<u8>();
            if target.is_null() {
                let _ = GlobalFree(Some(block));
                return Err("cannot lock clipboard memory".into());
            }
            std::ptr::copy_nonoverlapping(bytes.as_ptr(), target, bytes.len());
            let _ = GlobalUnlock(block);
            if let Err(e) = SetClipboardData(format, Some(HANDLE(block.0))) {
                let _ = GlobalFree(Some(block));
                return Err(Error::Win32 { context: "write the clipboard", source: e });
            }
        }
        Ok(())
    }

    /// Copies the bytes of a memory-backed format.
    fn get(&self, format: u32) -> Option<Vec<u8>> {
        // SAFETY: the clipboard is open; the global block is valid for
        // `GlobalSize` bytes while locked and is not freed by us.
        unsafe {
            let block = HGLOBAL(GetClipboardData(format).ok()?.0);
            let source = GlobalLock(block).cast::<u8>().cast_const();
            if source.is_null() {
                return None;
            }
            let bytes = std::slice::from_raw_parts(source, GlobalSize(block)).to_vec();
            let _ = GlobalUnlock(block);
            Some(bytes)
        }
    }

    /// Every format currently on the clipboard.
    fn formats(&self) -> Vec<u32> {
        let mut formats = Vec::new();
        let mut format = 0;
        loop {
            // SAFETY: the clipboard is open.
            format = unsafe { EnumClipboardFormats(format) };
            if format == 0 {
                return formats;
            }
            formats.push(format);
        }
    }
}

impl Drop for OpenClipboard {
    fn drop(&mut self) {
        // SAFETY: matches the successful OpenClipboard.
        let _ = unsafe { CloseClipboard() };
    }
}

fn register(name: &str) -> u32 {
    let name = wide(name);
    // SAFETY: `name` is NUL-terminated.
    unsafe { RegisterClipboardFormatW(PCWSTR(name.as_ptr())) }
}

fn utf16_bytes(text: &str) -> Vec<u8> {
    text.encode_utf16().chain(std::iter::once(0)).flat_map(u16::to_le_bytes).collect()
}

fn from_utf16_bytes(bytes: &[u8]) -> String {
    let units: Vec<u16> =
        bytes.as_chunks::<2>().0.iter().map(|&pair| u16::from_le_bytes(pair)).take_while(|&u| u != 0).collect();
    String::from_utf16_lossy(&units)
}

/// Reads the clipboard as text, if it holds any.
pub fn get_text() -> Option<String> {
    // SAFETY: querying availability needs no open clipboard.
    unsafe { IsClipboardFormatAvailable(CF_UNICODETEXT) }.ok()?;
    let clipboard = OpenClipboard::open().ok()?;
    clipboard.get(CF_UNICODETEXT).map(|bytes| from_utf16_bytes(&bytes))
}

/// Replaces the clipboard with `text`. With `transient`, the entry is kept out
/// of clipboard history and cloud sync. Returns the new sequence number.
///
/// # Errors
/// Fails when the clipboard is busy or cannot be written.
pub fn set_text(text: &str, transient: bool) -> Result<u32> {
    {
        let clipboard = OpenClipboard::open()?;
        clipboard.empty()?;
        clipboard.set(CF_UNICODETEXT, &utf16_bytes(text))?;
        if transient {
            for name in PRIVACY_FORMATS {
                let _ = clipboard.set(register(name), &0u32.to_le_bytes());
            }
        }
    }
    Ok(sequence_number())
}

/// Changes whenever any application writes to the clipboard.
pub fn sequence_number() -> u32 {
    // SAFETY: no preconditions.
    unsafe { GetClipboardSequenceNumber() }
}

/// All memory-backed clipboard formats, for restoring after a paste.
#[derive(Debug, Default)]
pub struct Snapshot {
    items: Vec<(u32, Vec<u8>)>,
}

impl Snapshot {
    pub fn capture() -> Snapshot {
        let Ok(clipboard) = OpenClipboard::open() else { return Snapshot::default() };
        let items = clipboard
            .formats()
            .into_iter()
            .filter(|f| !NON_GLOBAL_FORMATS.contains(f))
            .filter_map(|f| clipboard.get(f).map(|bytes| (f, bytes)))
            .collect();
        Snapshot { items }
    }

    /// Puts the captured contents (or emptiness) back.
    ///
    /// # Errors
    /// Fails when the clipboard is busy.
    pub fn restore(&self) -> Result<()> {
        let clipboard = OpenClipboard::open()?;
        clipboard.empty()?;
        for (format, bytes) in &self.items {
            // Synthesized formats (e.g. CF_TEXT from CF_UNICODETEXT) may fail; that's fine.
            let _ = clipboard.set(*format, bytes);
        }
        Ok(())
    }
}
