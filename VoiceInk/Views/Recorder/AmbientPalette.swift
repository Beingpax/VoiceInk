import SwiftUI

/// Colours for the ambient light, in two schemes.
///
/// **Why a second scheme is needed at all.** The dark scheme works by adding light: pale, low
/// chroma colours, wide soft bloom, white text. Added light only reads against something darker
/// than itself, so on a white document the entire effect disappears — a pale mint glow over a white
/// page is a pale mint page. Turning the opacity up does not rescue it either; it just makes a
/// washed-out haze.
///
/// So the light scheme inverts the physics rather than the palette. The colours go deep and
/// saturated, the bloom tightens, the rim gets stronger, and the text goes near-black. The light
/// stops behaving like a glow and starts behaving like ink soaking into the edge of the page. It is
/// the same instrument — colour for state, thickness for level — expressed in a medium that a light
/// background can actually carry.
///
/// **On detection.** This follows the app's appearance (System / Light / Dark in Settings), not a
/// reading of the pixels underneath. Sampling the actual background would mean capturing the screen
/// continuously, which needs Screen Recording permission and is a wildly disproportionate thing to
/// ask for a colour choice. The appearance setting is the honest proxy, and it is directly
/// overridable when the proxy is wrong.
struct AmbientPalette {
    let isLight: Bool

    static func resolve(_ colorScheme: ColorScheme) -> AmbientPalette {
        AmbientPalette(isLight: colorScheme == .light)
    }

    // MARK: - State colours

    func color(for state: AmbientState) -> Color {
        switch state {
        case .hidden:
            return .clear
        case .problem:
            return isLight
                ? Color(red: 0.78, green: 0.12, blue: 0.10)
                : Color(red: 0.97, green: 0.42, blue: 0.36)
        case .working:
            return isLight
                ? Color(red: 0.76, green: 0.42, blue: 0.02)
                : Color(red: 0.98, green: 0.72, blue: 0.35)
        case .listening, .settled:
            return isLight
                ? Color(red: 0.02, green: 0.47, blue: 0.36)
                : Color(red: 0.38, green: 0.86, blue: 0.68)
        }
    }

    // MARK: - How the light behaves
    //
    // On a dark ground the effect is mostly bloom with a faint rim. On a light one that reads as
    // haze, so the weighting flips: less spread, more edge.

    /// Multiplier on every alpha. Ink on paper has to commit harder than light in a dark room.
    var alphaScale: Double { isLight ? 1.35 : 1 }
    /// Multiplier on every blur radius.
    var blurScale: Double { isLight ? 0.55 : 1 }
    /// Multiplier on the contour hairline, which is what carries the shape on a light ground.
    var rimScale: Double { isLight ? 1.9 : 1 }

    // MARK: - Text

    /// Captions sit on their own bloom, so they follow the bloom rather than the background.
    var textPrimary: Color {
        isLight ? Color.black.opacity(0.9) : Color.white.opacity(0.94)
    }

    var textSecondary: Color {
        isLight ? Color.black.opacity(0.62) : Color.white.opacity(0.6)
    }

    var textTertiary: Color {
        isLight ? Color.black.opacity(0.45) : Color.white.opacity(0.45)
    }

    /// Floor for the transcript's oldest visible words. A word too faint to read still occupies the
    /// line and the eye still tries.
    var transcriptFadeFloor: Double { isLight ? 0.34 : 0.42 }

    /// The scrim behind text. Dark under white text, light under black text — in both cases it is
    /// blurred well past its own bounds so it never resolves into a container.
    var bloomFill: Color {
        isLight ? Color.white.opacity(0.82) : Color.black.opacity(0.55)
    }

    /// The shadow that makes glyphs sharp. Contrast does this job; glow only makes it foggy.
    var textShadow: Color {
        isLight ? Color.white.opacity(0.9) : Color.black.opacity(0.9)
    }

    var separator: Color {
        isLight ? Color.black.opacity(0.22) : Color.white.opacity(0.28)
    }
}

private struct AmbientPaletteKey: EnvironmentKey {
    static let defaultValue = AmbientPalette(isLight: false)
}

extension EnvironmentValues {
    var ambientPalette: AmbientPalette {
        get { self[AmbientPaletteKey.self] }
        set { self[AmbientPaletteKey.self] = newValue }
    }
}
