import AppKit
import SwiftUI
import Testing

@testable import VoiceInk

/// Holds both colour schemes to a measured contrast floor.
///
/// The light scheme shipped twice before it worked, and both failures were the same mistake made in
/// different places: colours picked for how vivid they looked rather than how they would land on
/// the ground they had to sit on. The second attempt averaged 3.4:1 against white, with the amber
/// at 2.48:1 — effectively invisible — while the dark scheme was sitting comfortably at 10.5:1
/// against black. Nothing caught it, because nothing was looking.
///
/// Saturation and legibility-on-white pull in opposite directions: a vivid orange is a *bright*
/// orange, and brightness is exactly what a white page already has. The only reliable check is the
/// number, so it is asserted here rather than judged by eye.
@MainActor
struct AmbientPaletteTests {

    /// WCAG relative luminance. sRGB components have to be linearised first — averaging the raw
    /// 0…1 values is the shortcut that makes bright colours look darker on paper than they are.
    private func luminance(_ color: Color) -> Double {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else {
            Issue.record("colour is not representable in sRGB")
            return 0
        }
        func linear(_ c: CGFloat) -> Double {
            let v = Double(c)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(srgb.redComponent)
            + 0.7152 * linear(srgb.greenComponent)
            + 0.0722 * linear(srgb.blueComponent)
    }

    private func contrast(_ color: Color, against ground: Double) -> Double {
        let a = luminance(color) + 0.05
        let b = ground + 0.05
        return max(a, b) / min(a, b)
    }

    /// WCAG AA for normal text. The light on screen is not text, but it has to be *read* — the
    /// difference between "recording" and "too loud" is carried entirely by hue.
    private let floor = 4.5
    private let litStates: [AmbientState] = [.listening, .working, .problem, .settled]

    @Test func theDarkSchemeReadsOnBlack() {
        let palette = AmbientPalette(isLight: false)
        for state in litStates {
            let ratio = contrast(palette.color(for: state), against: 0)
            #expect(ratio >= floor, "\(state) is \(ratio):1 against black")
        }
    }

    @Test func theLightSchemeReadsOnWhite() {
        // The assertion that would have caught both failed attempts.
        let palette = AmbientPalette(isLight: true)
        for state in litStates {
            let ratio = contrast(palette.color(for: state), against: 1)
            #expect(ratio >= floor, "\(state) is \(ratio):1 against white")
        }
    }

    @Test func theLightSchemeIsActuallyDarkerThanTheDarkOne() {
        // The inversion that makes the whole thing work. If a future edit "brightens" the light
        // scheme to make it livelier, this is what fails.
        let light = AmbientPalette(isLight: true)
        let dark = AmbientPalette(isLight: false)
        for state in litStates {
            #expect(luminance(light.color(for: state)) < luminance(dark.color(for: state)))
        }
    }

    /// CIE Lab, so distance between two colours can be measured the way an eye judges it rather
    /// than by brightness alone.
    private func lab(_ color: Color) -> (Double, Double, Double) {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return (0, 0, 0) }
        func linear(_ c: CGFloat) -> Double {
            let v = Double(c)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let r = linear(srgb.redComponent)
        let g = linear(srgb.greenComponent)
        let b = linear(srgb.blueComponent)

        // D65.
        let x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
        let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : (7.787 * t + 16.0 / 116.0) }

        return (116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)))
    }

    private func perceptualDistance(_ a: Color, _ b: Color) -> Double {
        let (l1, a1, b1) = lab(a)
        let (l2, a2, b2) = lab(b)
        return ((l1 - l2) * (l1 - l2) + (a1 - a2) * (a1 - a2) + (b1 - b2) * (b1 - b2)).squareRoot()
    }

    @Test func theStatesStayTellableApart() {
        // Measured as Lab distance, not luminance ratio. The first version of this test compared
        // luminance and failed — on the *dark* palette, which has been fine all along. Two hues at
        // the same lightness sit at a ~1.0 luminance ratio while being obviously different colours,
        // so that metric was answering a question nobody asked. Anything past ~25 dE is
        // comfortably distinct; the closest pair here is bronze against oxblood at ~38.
        //
        // dE says nothing about colour-vision deficiency, and green/amber/red is exactly the axis
        // that fails there. The mitigation is not in this file: no state is carried by colour
        // alone. A problem always writes the reason, processing always sweeps, and listening always
        // modulates. Colour is the fastest channel here, never the only one.
        for palette in [AmbientPalette(isLight: true), AmbientPalette(isLight: false)] {
            let distinct: [AmbientState] = [.listening, .working, .problem]
            for (index, first) in distinct.enumerated() {
                for second in distinct.dropFirst(index + 1) {
                    let distance = perceptualDistance(
                        palette.color(for: first), palette.color(for: second))
                    #expect(
                        distance >= 25,
                        "\(first) and \(second) are only \(distance) apart in \(palette.isLight ? "light" : "dark")"
                    )
                }
            }
        }
    }

    /// Approximates how a deuteranope (red-green colour blind, ~6% of men) sees a colour, by
    /// collapsing the M cone onto L in LMS space.
    private func deuteranope(_ color: Color) -> Color {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return color }
        func linear(_ c: CGFloat) -> Double {
            let v = Double(c)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let r = linear(srgb.redComponent)
        let g = linear(srgb.greenComponent)
        let b = linear(srgb.blueComponent)

        let l = 17.8824 * r + 43.5161 * g + 4.11935 * b
        let s = 0.0299566 * r + 0.184309 * g + 1.46709 * b
        let m = 0.494207 * l + 1.24827 * s

        func encode(_ v: Double) -> Double {
            let clamped = min(max(v, 0), 1)
            return clamped <= 0.0031308
                ? 12.92 * clamped : 1.055 * pow(clamped, 1 / 2.4) - 0.055
        }
        return Color(
            red: encode(0.080944 * l - 0.130504 * m + 0.116721 * s),
            green: encode(-0.0102485 * l + 0.0540194 * m - 0.113615 * s),
            blue: encode(-0.000365294 * l - 0.00412163 * m + 0.693513 * s)
        )
    }

    @Test func theStatesSurviveColourBlindness() {
        // Green/amber/red is the classic trap, and the light scheme walked straight into it: a deep
        // bronze and a pure oxblood measured 11.6 dE for a deuteranope — the same colour, in
        // practice. Both light colours now carry blue, which is the channel that survives.
        //
        // Redundancy elsewhere is still the real defence — a problem always writes the reason —
        // but colour is the fastest channel, and it should not be actively misleading.
        for palette in [AmbientPalette(isLight: true), AmbientPalette(isLight: false)] {
            let distinct: [AmbientState] = [.listening, .working, .problem]
            for (index, first) in distinct.enumerated() {
                for second in distinct.dropFirst(index + 1) {
                    let distance = perceptualDistance(
                        deuteranope(palette.color(for: first)),
                        deuteranope(palette.color(for: second))
                    )
                    #expect(
                        distance >= 20,
                        "\(first) and \(second) collapse to \(distance) dE for a deuteranope in \(palette.isLight ? "light" : "dark")"
                    )
                }
            }
        }
    }

    @Test func textAndItsScrimAgree() {
        // The scrim is what the caption is read against, so they have to be opposites. Getting
        // this backwards produces white text on a white pool, which is invisible rather than ugly.
        for palette in [AmbientPalette(isLight: true), AmbientPalette(isLight: false)] {
            let text = luminance(palette.textPrimary)
            let scrim = luminance(palette.bloomFill)
            #expect(
                palette.isLight ? text < scrim : text > scrim,
                "text and scrim are the same way round in \(palette.isLight ? "light" : "dark")"
            )
        }
    }

    @Test func settledBorrowsTheListeningColour() {
        // The afterglow is the same light calming down, not a fourth thing to learn.
        for palette in [AmbientPalette(isLight: true), AmbientPalette(isLight: false)] {
            #expect(palette.color(for: .listening) == palette.color(for: .settled))
        }
    }

    @Test func hiddenDrawsNothing() {
        for palette in [AmbientPalette(isLight: true), AmbientPalette(isLight: false)] {
            #expect(palette.color(for: .hidden) == .clear)
        }
    }

    // MARK: - Mode resolution

    @Test func autoFollowsTheAppearance() {
        #expect(AmbientPalette.resolve(.light, mode: .auto).isLight)
        #expect(!AmbientPalette.resolve(.dark, mode: .auto).isLight)
    }

    @Test func anExplicitChoiceOverridesTheAppearance() {
        // The whole point of the override: a dark-mode system full of white documents.
        #expect(AmbientPalette.resolve(.dark, mode: .light).isLight)
        #expect(!AmbientPalette.resolve(.light, mode: .dark).isLight)
    }
}
