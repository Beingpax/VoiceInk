//! Win32 icons created from [`crate::artwork`] at runtime (no resource
//! compiler needed).

pub use crate::artwork::IconState;
use crate::artwork::render_bgra;
use windows::Win32::Graphics::Gdi::{CreateBitmap, DeleteObject, HGDIOBJ};
use windows::Win32::UI::WindowsAndMessaging::{CreateIconIndirect, DestroyIcon, HICON, ICONINFO};

/// An icon handle destroyed on drop.
#[derive(Debug)]
pub struct OwnedIcon(HICON);

impl OwnedIcon {
    pub fn handle(&self) -> HICON {
        self.0
    }
}

impl Drop for OwnedIcon {
    fn drop(&mut self) {
        // SAFETY: the icon was created by CreateIconIndirect and is destroyed once.
        let _ = unsafe { DestroyIcon(self.0) };
    }
}

/// Creates a `size`×`size` icon for `state`.
pub fn create_icon(size: usize, state: IconState) -> Option<OwnedIcon> {
    let pixels = render_bgra(size, state);
    let edge = i32::try_from(size).ok()?;
    // 1-bpp mask rows are padded to 16 bits; all-zero means "use the alpha channel".
    let mask_bits = vec![0u8; size.div_ceil(16) * 2 * size];
    // SAFETY: both bitmaps are created from buffers of the exact size GDI
    // reads; CreateIconIndirect copies them, so they are deleted afterwards.
    unsafe {
        let color_bitmap = CreateBitmap(edge, edge, 1, 32, Some(pixels.as_ptr().cast()));
        let mask_bitmap = CreateBitmap(edge, edge, 1, 1, Some(mask_bits.as_ptr().cast()));
        let info =
            ICONINFO { fIcon: true.into(), xHotspot: 0, yHotspot: 0, hbmMask: mask_bitmap, hbmColor: color_bitmap };
        let icon = CreateIconIndirect(&raw const info).ok().map(OwnedIcon);
        let _ = DeleteObject(HGDIOBJ(color_bitmap.0));
        let _ = DeleteObject(HGDIOBJ(mask_bitmap.0));
        icon
    }
}
