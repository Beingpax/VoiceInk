//! Tray/overlay icons drawn at runtime (no resource compiler needed).
//!
//! A rounded microphone glyph on a coloured disc; the colour reflects the state.

use windows::Win32::Graphics::Gdi::{CreateBitmap, DeleteObject, HGDIOBJ};
use windows::Win32::UI::WindowsAndMessaging::{CreateIconIndirect, DestroyIcon, HICON, ICONINFO};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IconState {
    Idle,
    Recording,
    Busy,
}

impl IconState {
    fn color(self) -> (u8, u8, u8) {
        match self {
            IconState::Idle => (0x3B, 0x82, 0xF6),      // blue
            IconState::Recording => (0xEF, 0x44, 0x44), // red
            IconState::Busy => (0xF5, 0x9E, 0x0B),      // amber
        }
    }
}

/// Coverage (0..=1) of the microphone glyph at a point in a unit square.
fn mic_coverage(x: f32, y: f32) -> f32 {
    // Capsule body.
    let (cx, top, bottom, r) = (0.5, 0.22, 0.52, 0.12);
    let dy = if y < top {
        top - y
    } else if y > bottom {
        y - bottom
    } else {
        0.0
    };
    let body = ((x - cx).hypot(dy) - r).max(-0.02);
    // U-shaped holder: ring segment below the capsule.
    let ring_r = 0.21;
    let ring = ((x - cx).hypot(y - 0.45) - ring_r).abs() - 0.035;
    let ring = if y < 0.45 { 1.0 } else { ring };
    // Stem and base.
    let stem = if (x - cx).abs() < 0.035 && (0.66..0.8).contains(&y) { -1.0 } else { 1.0 };
    let base = if (x - cx).abs() < 0.16 && (0.78..0.83).contains(&y) { -1.0 } else { 1.0 };
    let d = body.min(ring).min(stem).min(base);
    (0.5 - d * 32.0).clamp(0.0, 1.0)
}

/// Renders a 32-bit premultiplied BGRA image of the icon.
pub fn render(size: usize, state: IconState) -> Vec<u8> {
    let (red, green, blue) = state.color();
    let mut pixels = vec![0u8; size * size * 4];
    for (index, pixel) in pixels.as_chunks_mut::<4>().0.iter_mut().enumerate() {
        let x = ((index % size) as f32 + 0.5) / size as f32;
        let y = ((index / size) as f32 + 0.5) / size as f32;
        let alpha = (0.5 - ((x - 0.5).hypot(y - 0.5) - 0.48) * size as f32).clamp(0.0, 1.0);
        let glyph = mic_coverage(x, y);
        // White glyph over the coloured disc, premultiplied by the disc's alpha.
        let shade = |channel: u8| ((f32::from(channel) * (1.0 - glyph) + 255.0 * glyph) * alpha) as u8;
        *pixel = [shade(blue), shade(green), shade(red), (alpha * 255.0) as u8];
    }
    pixels
}

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
    let pixels = render(size, state);
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
