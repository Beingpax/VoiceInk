import SwiftUI

/// How the ambient light should be drawn for the background it is sitting on.
///
/// Follows the app's appearance by default, and can be forced. The appearance setting is a proxy —
/// reading the actual pixels underneath would mean capturing the screen continuously, which needs
/// Screen Recording permission and is a wildly disproportionate ask for a colour choice — so the
/// override exists for when the proxy is wrong, such as a dark-mode system full of white documents.
enum AmbientBackgroundMode: String, CaseIterable, Identifiable {
    case auto
    case dark
    case light

    static let userDefaultsKey = "AmbientBackgroundMode"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return String(localized: "Match appearance")
        case .dark: return String(localized: "Tuned for dark backgrounds")
        case .light: return String(localized: "Tuned for light backgrounds")
        }
    }

    static var stored: AmbientBackgroundMode {
        let raw = UserDefaults.standard.string(forKey: userDefaultsKey) ?? Self.auto.rawValue
        return AmbientBackgroundMode(rawValue: raw) ?? .auto
    }
}

/// Colours for the ambient light, in two schemes.
///
/// **The first attempt at a light scheme failed, and it is worth recording why.** It changed the
/// colours — deeper, more saturated — and left the compositing alone. Every layer here is drawn
/// with ordinary source-over alpha, and that is the whole problem: colour over black *is* the
/// colour, so it reads as light; colour over white washes toward white at any alpha below 1, no
/// matter how saturated the source. Turning the alpha up does not rescue it either. It just walks
/// the band from invisible haze to an opaque coloured rectangle, which is the exact thing this
/// design exists to avoid. A glow cannot be added to something already at full brightness.
///
/// So the light scheme stops trying to be a glow. It becomes **ink**: narrower, denser and much
/// sharper. The band contracts, the blur tightens hard, the colour goes to near-full strength
/// against the bezel, and the contour — nearly decorative on black — becomes the main event, with a
/// tight dark shadow beneath it so the edge sits *above* the page rather than staining it.
///
/// A first attempt at this laid a wide dark vignette over the whole band and put colour on top. It
/// is the right instinct — the colour does need something darker than itself — but at that radius
/// the darkness reads as a grey smudge across the top of the screen. Localising it to a few points
/// under the contour gives the same lift with none of the haze.
struct AmbientPalette {
    let isLight: Bool

    static func resolve(
        _ colorScheme: ColorScheme, mode: AmbientBackgroundMode = .stored
    ) -> AmbientPalette {
        switch mode {
        case .dark: return AmbientPalette(isLight: false)
        case .light: return AmbientPalette(isLight: true)
        case .auto: return AmbientPalette(isLight: colorScheme == .light)
        }
    }

    // MARK: - State colours

    func color(for state: AmbientState) -> Color {
        switch state {
        case .hidden:
            return .clear
        case .problem:
            return isLight
                ? Color(red: 0.86, green: 0.16, blue: 0.12)
                : Color(red: 0.97, green: 0.42, blue: 0.36)
        case .working:
            return isLight
                ? Color(red: 0.94, green: 0.55, blue: 0.05)
                : Color(red: 0.98, green: 0.72, blue: 0.35)
        case .listening, .settled:
            return isLight
                ? Color(red: 0.05, green: 0.66, blue: 0.47)
                : Color(red: 0.38, green: 0.86, blue: 0.68)
        }
    }

    // MARK: - How the light behaves
    //
    // On a dark ground the effect is mostly bloom with a faint rim. On a light one that reads as
    // haze, so the weighting flips: less spread, more edge.

    /// A tight dark shadow directly beneath the contour, so the edge reads as sitting above the
    /// page. Localised on purpose — spread across the whole band it is just a grey smudge.
    var contourShadow: Double { isLight ? 0.34 : 0 }
    /// Multiplier on every blur radius. Light grounds cannot carry spread; it becomes haze.
    var blurScale: Double { isLight ? 0.4 : 1 }
    /// How wide the light band is. Narrower on light, where density does the work width cannot.
    var bandScale: Double { isLight ? 0.62 : 1 }
    /// Multiplier on the contour hairline, the main event on a light ground.
    var rimScale: Double { isLight ? 2.4 : 1 }

    /// The wide outer bloom. Nearly pointless on white, so it mostly steps aside.
    var haloAlpha: Double { isLight ? 0.18 : 0.34 }
    /// The band's own body, against the bezel and where it fades out.
    var coreAlphaTop: Double { isLight ? 0.98 : 0.80 }
    var coreAlphaMid: Double { isLight ? 0.62 : 0.34 }
    var rimAlpha: Double { isLight ? 0.95 : 0.75 }

    /// The screen-edge wash and the notch halo, which are SwiftUI strokes rather than Canvas.
    var frameCoreAlpha: Double { isLight ? 1.0 : 0.85 }
    var frameRimAlpha: Double { isLight ? 0.95 : 0.5 }
    var frameRimWidth: CGFloat { isLight ? 2 : 1 }
    var notchHaloAlpha: Double { isLight ? 0.72 : 0.45 }
    var notchRimAlpha: Double { isLight ? 0.95 : 0.40 }

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
        isLight ? Color.white.opacity(0.9) : Color.black.opacity(0.55)
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
