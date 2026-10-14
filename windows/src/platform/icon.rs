//! Tray/overlay icons drawn at runtime (no resource compiler needed).
//!
//! A rounded microphone glyph on a coloured disc; the colour reflects the state.

use windows::Win32::Graphics::Gdi::{CreateBitmap, DeleteObject, HGDIOBJ};
use windows::Win32::UI::WindowsAndMessaging::{CreateIconIndirect, HICON, ICONINFO};

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
    let stem = if (x - cx).abs() < 0.035 && (0.66..0.8).contains(&y) {
        -1.0
    } else {
        1.0
    };
    let base = if (x - cx).abs() < 0.16 && (0.78..0.83).contains(&y) {
        -1.0
    } else {
        1.0
    };
    let d = body.min(ring).min(stem).min(base);
    (0.5 - d * 32.0).clamp(0.0, 1.0)
}

/// Renders a 32-bit premultiplied BGRA image of the icon.
pub fn render(size: usize, state: IconState) -> Vec<u8> {
    let (r, g, b) = state.color();
    let mut px = vec![0u8; size * size * 4];
    for py in 0..size {
        for pxi in 0..size {
            let x = (pxi as f32 + 0.5) / size as f32;
            let y = (py as f32 + 0.5) / size as f32;
            let disc = (0.5 - ((x - 0.5).hypot(y - 0.5) - 0.48) * size as f32).clamp(0.0, 1.0);
            let glyph = mic_coverage(x, y);
            // White glyph over the coloured disc.
            let cr = r as f32 * (1.0 - glyph) + 255.0 * glyph;
            let cg = g as f32 * (1.0 - glyph) + 255.0 * glyph;
            let cb = b as f32 * (1.0 - glyph) + 255.0 * glyph;
            let a = disc;
            let i = (py * size + pxi) * 4;
            px[i] = (cb * a) as u8;
            px[i + 1] = (cg * a) as u8;
            px[i + 2] = (cr * a) as u8;
            px[i + 3] = (a * 255.0) as u8;
        }
    }
    px
}

pub fn create_icon(size: usize, state: IconState) -> Option<HICON> {
    let pixels = render(size, state);
    unsafe {
        let color = CreateBitmap(
            size as i32,
            size as i32,
            1,
            32,
            Some(pixels.as_ptr() as *const _),
        );
        let mask_bits = vec![0u8; size.div_ceil(16) * 2 * size];
        let mask = CreateBitmap(
            size as i32,
            size as i32,
            1,
            1,
            Some(mask_bits.as_ptr() as *const _),
        );
        let info = ICONINFO {
            fIcon: true.into(),
            xHotspot: 0,
            yHotspot: 0,
            hbmMask: mask,
            hbmColor: color,
        };
        let icon = CreateIconIndirect(&info).ok();
        let _ = DeleteObject(HGDIOBJ(color.0));
        let _ = DeleteObject(HGDIOBJ(mask.0));
        icon
    }
}
