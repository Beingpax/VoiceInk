//! The app icon, drawn in code: a rounded microphone glyph on a coloured
//! disc whose colour reflects the state. Used for the tray icon (Win32) and
//! the settings window icon (iced).

// Pixel maths on small, bounded image sizes.
#![allow(clippy::cast_possible_truncation, clippy::cast_precision_loss, clippy::cast_sign_loss)]

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

/// Renders the icon as premultiplied BGRA (the GDI bitmap layout).
pub fn render_bgra(size: usize, state: IconState) -> Vec<u8> {
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

/// Renders the icon as straight (non-premultiplied) RGBA.
pub fn render_rgba(size: usize, state: IconState) -> Vec<u8> {
    let mut pixels = render_bgra(size, state);
    for pixel in pixels.as_chunks_mut::<4>().0 {
        let [blue, green, red, alpha] = *pixel;
        let unmultiply = |channel: u8| {
            if alpha == 0 { 0 } else { (u32::from(channel) * 255 / u32::from(alpha)).min(255) as u8 }
        };
        *pixel = [unmultiply(red), unmultiply(green), unmultiply(blue), alpha];
    }
    pixels
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn corners_are_transparent_and_centre_is_opaque() {
        let size = 32;
        let pixels = render_rgba(size, IconState::Idle);
        assert_eq!(pixels.len(), size * size * 4);
        assert_eq!(pixels[3], 0, "top-left corner is outside the disc");
        let centre = (size / 2 * size + size / 2) * 4;
        assert_eq!(pixels[centre + 3], 255);
    }
}
