import SwiftUI

/// How the ambient light should be drawn for the background it is sitting on.
///
/// `auto` follows the theme of the window you are dictating into, measured rather than inferred —
/// see `AmbientBackgroundSensor`. The overrides remain for when that is unavailable (no Screen
/// Recording permission) or simply not what you want.
enum AmbientBackgroundMode: String, CaseIterable, Identifiable {
    case auto
    case dark
    case light

    static let userDefaultsKey = "AmbientBackgroundMode"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return String(localized: "Match the app I'm dictating into")
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

    /// - Parameter measuredLight: what the background actually is, when it could be measured.
    ///   Deliberately *not* the app's `colorScheme`: that reflects the appearance preference for
    ///   VoiceInk's own windows, and wanting dark app chrome on a Light Mode Mac says nothing about
    ///   the white document the light is drawn over. Reading it here is what put the mint green on
    ///   a white page.
    static func resolve(
        measuredLight: Bool, mode: AmbientBackgroundMode = .stored
    ) -> AmbientPalette {
        switch mode {
        case .dark: return AmbientPalette(isLight: false)
        case .light: return AmbientPalette(isLight: true)
        case .auto: return AmbientPalette(isLight: measuredLight)
        }
    }

    // MARK: - State colours
    //
    // Measured, not eyeballed. The dark set averages 10.5:1 against black. The first light set was
    // chosen by saturation and averaged 3.4:1 against white — the amber sat at 2.48:1, which is
    // close to invisible. Saturation is not what makes a colour visible on white; *low luminance*
    // is, and those two pull in opposite directions. A vivid orange is a bright orange.
    //
    // So the light set is deep ink rather than bright pigment. AmbientPaletteTests holds both sets
    // above 4.5:1 against their own ground so this cannot quietly regress.
    //
    // The first deep set used a forest green for listening and it looked murky, for a reason worth
    // keeping: **green is the hue that loses the most when you darken it.** Green carries 71% of
    // perceived luminance, so a green dark enough to read on white has had its green channel
    // crushed, and what is left is a dark slate. Measured as chroma: forest came out at 31 while
    // sitting at the same lightness where cobalt reaches 69. Blue contributes only 7% of luminance,
    // so it can be deep and still be intensely blue — it is the one hue that survives this.
    //
    // Blue also breaks the green/amber/red axis, which is the one that collapses under red-green
    // colour blindness. That is not a side benefit; it is why `problem` gained a blue lean too.
    // Bronze against a pure oxblood measured 11.6 dE for a deuteranope — near-identical — and the
    // wine-red below takes that to 26.6.

    func color(for state: AmbientState) -> Color {
        switch state {
        case .hidden:
            return .clear
        case .problem:
            return isLight
                ? Color(red: 0.70, green: 0.05, blue: 0.24)  // wine        6.93:1
                : Color(red: 0.97, green: 0.42, blue: 0.36)  // salmon      7.23:1
        case .working:
            return isLight
                ? Color(red: 0.62, green: 0.36, blue: 0.02)  // bronze      5.27:1
                : Color(red: 0.98, green: 0.72, blue: 0.35)  // amber      12.03:1
        case .listening, .settled:
            return isLight
                ? Color(red: 0.10, green: 0.28, blue: 0.72)  // cobalt      7.95:1
                : Color(red: 0.38, green: 0.86, blue: 0.68)  // mint       12.28:1
        }
    }

    /// The colour the crest's *body* is filled with, as opposed to its contour.
    ///
    /// The deep ink set is right for the frame and the rim, where the job is legibility against
    /// white. It is wrong for the waveform, which has a different job — a voice should look alive,
    /// and a dark blue at 7:1 contrast simply sits there. Mint works on black precisely because it
    /// is *bright*; the light scheme lost that when everything went deep.
    ///
    /// So the crest is two-tone on light backgrounds: a vivid core inside a deep contour. The rim
    /// still carries the legibility — it is the measured colour, unchanged — while the fill is free
    /// to be luminous, because it is bounded by something that is not.
    func crestCore(for state: AmbientState) -> Color {
        guard isLight else { return color(for: state) }

        switch state {
        case .hidden: return .clear
        case .problem: return Color(red: 0.92, green: 0.16, blue: 0.30)
        case .working: return Color(red: 0.97, green: 0.62, blue: 0.06)
        case .listening, .settled: return Color(red: 0.13, green: 0.45, blue: 0.98)
        }
    }

    // MARK: - How the light behaves
    //
    // On a dark ground the effect is mostly bloom with a faint rim. On a light one that reads as
    // haze, so the weighting flips: less spread, more edge.

    /// A tight dark shadow directly beneath the contour, so the edge reads as sitting above the
    /// page. Localised on purpose — spread across the whole band it is just a grey smudge.
    var contourShadow: Double { isLight ? 0.22 : 0 }
    /// Multiplier on every blur radius. Light grounds cannot carry spread; it becomes haze.
    var blurScale: Double { isLight ? 0.4 : 1 }
    /// How wide the light band is. Narrower on light, where density does the work width cannot.
    var bandScale: Double { isLight ? 0.62 : 1 }
    /// Multiplier on the contour hairline, the main event on a light ground.
    var rimScale: Double { isLight ? 2.4 : 1 }

    /// The wide outer bloom. Nearly pointless on white, so it mostly steps aside.
    var haloAlpha: Double { isLight ? 0.30 : 0.34 }
    /// The band's own body, against the bezel and where it fades out.
    var coreAlphaTop: Double { isLight ? 0.95 : 0.80 }
    var coreAlphaMid: Double { isLight ? 0.55 : 0.34 }
    /// The crest is the one element allowed to keep its spread on a light ground — it is the thing
    /// being looked at, and tightening it to match the frame is what made it lifeless.
    var crestBlurScale: Double { isLight ? 0.8 : 1 }
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
        // Not pure white: over a white page a white scrim is invisible, and the caption needs a
        // pool it can be seen to sit in rather than text floating on the document.
        isLight ? Color(white: 0.97).opacity(0.94) : Color.black.opacity(0.55)
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
