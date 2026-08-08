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
/// So the light scheme does not try to add light. It **borrows darkness first**: a soft dark
/// vignette is laid down in the same shape, and the colour goes on top of that. The colour now has
/// something darker than itself to be light against, which is the condition the dark scheme gets
/// for free from the screen. Locally, the edge of the display becomes a dark surround with a lit
/// edge inside it — the same instrument, working the same way, on ground that could not otherwise
/// carry it.
///
/// The rim also does much more work here. A bloom is nearly meaningless on white; a defined contour
/// is not, so the hairline roughly doubles and the blur tightens.
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

    /// The darkness the colour is lit against. Drawn in the same shape, underneath everything, and
    /// the single reason the light scheme reads at all. Zero on a dark background, which already
    /// supplies its own.
    var vignette: Double { isLight ? 0.30 : 0 }
    /// Multiplier on every alpha.
    var alphaScale: Double { isLight ? 1.2 : 1 }
    /// Multiplier on every blur radius. Tighter on light, where spread becomes haze.
    var blurScale: Double { isLight ? 0.62 : 1 }
    /// Multiplier on the contour hairline, which is what carries the shape on a light ground.
    var rimScale: Double { isLight ? 2.2 : 1 }

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
