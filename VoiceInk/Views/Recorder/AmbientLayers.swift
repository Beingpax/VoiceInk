import AppKit
import SwiftUI

/// Where the display's edges and cutout are, resolved once and handed to every layer.
///
/// Shared rather than recomputed per view so the crest, the edge wash and the caption cannot
/// disagree about where the hardware is — a 1pt disagreement between the crest's baseline and the
/// notch halo shows up immediately as a seam.
struct AmbientGeometry: Equatable {
    var hasNotch: Bool
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var cornerRadius: CGFloat

    /// Width of the light band at silence and at full level. Most of the band sits off-screen, so
    /// what you see is its inward falloff — light seeping in from the bezel rather than a line
    /// drawn on top of your work.
    var minBloom: CGFloat = 30
    var maxBloom: CGFloat = 78

    /// Depth of the top-edge crest at rest and at full voice. The resting depth is what the crest
    /// hands off to the side edges at the corners, so it is deliberately close to `minBloom`.
    var crestBaseDepth: CGFloat = 24
    var crestPeakDepth: CGFloat = 52

    static func current() -> AmbientGeometry {
        let screen = NSScreen.main
        let inset = screen?.safeAreaInsets.top ?? 0
        let hasNotch = inset > 0

        let width: CGFloat = {
            guard let screen,
                let left = screen.auxiliaryTopLeftArea?.width,
                let right = screen.auxiliaryTopRightArea?.width
            else { return 180 }
            return screen.frame.width - left - right
        }()

        let height: CGFloat =
            hasNotch
            ? inset
            : (NSApplication.shared.mainMenu?.menuBarHeight ?? NSStatusBar.system.thickness)

        return AmbientGeometry(
            hasNotch: hasNotch,
            notchWidth: width,
            notchHeight: height,
            // macOS does not expose the display's physical corner radius. A squared-off glow fights
            // the rounded corners badly, and this is close enough that the light hugs the bezel.
            cornerRadius: hasNotch ? 12 : 8
        )
    }

    /// How far below the hardware edge the crest can reach at full voice.
    var crestExtent: CGFloat {
        (hasNotch ? notchHeight : 0) + crestBaseDepth + crestPeakDepth
    }

    /// Deliberately measured against a *typical* crest rather than its maximum reach. Clearing the
    /// loudest possible moment left a gap of dead screen most of the time and the caption floated
    /// unattached; sitting where the light usually ends means a loud passage laps over the words,
    /// which reads as text inside the glow rather than beneath it.
    var captionY: CGFloat {
        (hasNotch ? notchHeight : 0) + crestBaseDepth + crestPeakDepth * 0.42 + 12
    }

    var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
}

/// The fast-moving parts of a take, kept out of the main view's body.
///
/// This exists for a measured reason. With all of it as `@State` on `AmbientRecorderView`, every
/// 30Hz sample invalidated the whole surface — frame, crest, notch halo, caption, mode strip, take
/// bar — and `sample` put 12.2% of one core in `AG::Graph::UpdateStack::update`, SwiftUI walking
/// its graph to rediscover that only the waveform had moved. The drawing itself was 3.5%; deciding
/// what to draw cost nearly four times as much.
///
/// Because `@Observable` tracks reads per view rather than per object, moving these here means only
/// the leaf that actually reads `trace` re-renders when `trace` changes. The parent reads none of
/// them, so it stops re-evaluating at audio rate entirely.
@MainActor
@Observable
final class AmbientMeter {
    /// Rolling voice history for the crest. ~2s at the 30Hz sample rate.
    var trace: [Double] = []
    /// Damped level driving band thickness.
    var level: Double = 0
    var elapsed: TimeInterval = 0

    /// The whole take, kept so the crest can replay it while it is being transcribed.
    var takeSamples: [Double] = []
    var takeEnvelope: [Double] = []
    var indeterminateSweep: Double = 0

    /// Flips once per take rather than tracking a count. The parent needs to know whether a replay
    /// is possible, and reading `takeSamples.count` there would have reintroduced a 10Hz
    /// invalidation of the entire surface through the back door.
    var hasTake = false

    func beginTake() {
        trace = []
        takeSamples = []
        takeEnvelope = []
        elapsed = 0
        hasTake = false
    }

    func endTake() {
        level = 0
    }

    func append(_ sample: Double) {
        trace.append(sample)
        if trace.count > 64 { trace.removeFirst() }
    }

    func recordTakeSample(_ sample: Double) {
        takeSamples.append(sample)
        if !hasTake, takeSamples.count > 2 { hasTake = true }
    }

    /// The processing task folds the envelope a frame after the state flips. Folding inline for
    /// that one frame is what stops the crest blinking out and back on every take.
    var replayEnvelope: [Double] {
        takeEnvelope.isEmpty
            ? AmbientTakeEnvelope.downsample(takeSamples, to: 110)
            : takeEnvelope
    }
}

// MARK: - Layers

/// The screen-edge wash, the notch halo and the indeterminate lap.
///
/// Split out so that `level` — which changes 30 times a second — invalidates only this.
struct AmbientFrameLayer: View {
    let meter: AmbientMeter
    let state: AmbientState
    let geometry: AmbientGeometry
    let palette: AmbientPalette
    let tint: Color
    let showsPerimeterProgress: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The edge wash steps back when the notch is carrying the signal — but only a little. At the
    /// old 0.35 the edges were three times dimmer than the crest, and the two stopped reading as
    /// the same light.
    private var edgeIntensity: Double {
        geometry.hasNotch ? state.intensity * 0.62 : state.intensity
    }

    /// Quantised to 3pt steps on purpose. This drives a blurred stroke the size of the display,
    /// which is the most expensive thing drawn here, and at 30Hz it was being re-rendered for
    /// changes far below the threshold of sight.
    private var bloomWidth: CGFloat {
        guard state != .hidden else { return 0 }
        let band = geometry.minBloom
        let span = geometry.maxBloom - geometry.minBloom
        let exact =
            reduceMotion
            ? (geometry.minBloom + geometry.maxBloom) / 2
            : band + span * CGFloat(meter.level)
        return (exact * palette.bandScale / 3).rounded() * 3
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                edgeWash
                    .allowsHitTesting(false)

                if geometry.hasNotch {
                    notchGlow(in: geo.size)
                } else if showsPerimeterProgress {
                    perimeterProgress(in: geo.size)
                }
            }
            .allowsHitTesting(false)
        }
        .animation(.easeOut(duration: 0.14), value: bloomWidth)
    }

    /// Two layers: a wide, heavily blurred band pushed half off-screen so only its falloff is
    /// visible, and a crisp line right at the bezel to give the light an origin. A single
    /// hard-edged stroke reads as a rendering error rather than a glow.
    private var edgeWash: some View {
        ZStack {
            geometry.shape
                .stroke(
                    tint.opacity(palette.frameCoreAlpha * edgeIntensity), lineWidth: bloomWidth
                )
                .blur(radius: bloomWidth * 0.5 * palette.blurScale)
                .padding(-bloomWidth / 2)

            geometry.shape
                .stroke(
                    tint.opacity(palette.frameRimAlpha * edgeIntensity),
                    lineWidth: palette.frameRimWidth
                )
                .blur(radius: 0.5)
        }
    }

    /// Halo width around the cutout. Smaller range than the screen edge — the notch is a much
    /// tighter object and the same bloom would swallow it.
    private var notchHalo: CGFloat {
        guard state != .hidden else { return 0 }
        guard !reduceMotion else { return 11 }
        return 6 + 11 * CGFloat(meter.level)
    }

    /// Light spilling around the camera housing, hugging the cutout's own contour.
    ///
    /// The notch-appropriate form of the same idea: the border is still the instrument, but on a
    /// notched display the instrument is the notch. The cutout is physically black and unlit, so a
    /// halo around it reads as the hardware itself glowing — which the screen edge cannot do,
    /// because it has content behind it.
    private func notchGlow(in size: CGSize) -> some View {
        let shape = NotchShape(topCornerRadius: 6, bottomCornerRadius: 13)

        return ZStack {
            shape
                .stroke(
                    tint.opacity(palette.notchHaloAlpha * state.intensity), lineWidth: notchHalo
                )
                .blur(radius: notchHalo * 0.7 * palette.blurScale)

            // Crisp contour so the halo has a defined source. Faint on dark, where at full strength
            // it outlined the cutout like a sticker; strong on light, where it is all there is.
            shape
                .stroke(
                    tint.opacity(palette.notchRimAlpha * state.intensity),
                    lineWidth: palette.frameRimWidth
                )
                .blur(radius: 0.8 * palette.blurScale)

            if showsPerimeterProgress {
                // Progress laps the cutout rather than the whole screen — a far shorter circuit, so
                // the same duration reads as a much more legible rate of travel.
                lap(around: AnyShape(shape), period: 2.4, width: 8, coreWidth: 2)
            }
        }
        .frame(width: geometry.notchWidth, height: geometry.notchHeight)
        .position(x: size.width / 2, y: geometry.notchHeight / 2)
    }

    /// A light completing one lap of the perimeter.
    private func perimeterProgress(in size: CGSize) -> some View {
        lap(around: AnyShape(geometry.shape), period: 3, width: 16, coreWidth: 2.5)
            .frame(width: size.width, height: size.height)
    }

    /// A comet: a soft wide tail with a brighter core, so it reads as a moving light rather than a
    /// sliding segment of rectangle.
    private func lap(
        around shape: AnyShape, period: Double, width: CGFloat, coreWidth: CGFloat
    ) -> some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let position =
                context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: period) / period

            ZStack {
                shape
                    .trim(from: position, to: min(position + 0.16, 1))
                    .stroke(
                        tint.opacity(0.7), style: StrokeStyle(lineWidth: width, lineCap: .round)
                    )
                    .blur(radius: width * 0.6 * palette.blurScale)

                shape
                    .trim(from: position, to: min(position + 0.06, 1))
                    .stroke(tint, style: StrokeStyle(lineWidth: coreWidth, lineCap: .round))
                    .blur(radius: 1)
            }
        }
    }
}

/// The crest. Split out so that `trace` — 30 appends a second — invalidates only this.
struct AmbientCrestLayer: View {
    let meter: AmbientMeter
    let phase: AmbientCrestPhase
    let state: AmbientState
    let geometry: AmbientGeometry
    let palette: AmbientPalette
    let tint: Color
    let estimate: RecorderProcessingEstimate

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far out the replay has travelled.
    ///
    /// With history behind it this is the real predicted progress. Without, it is a repeating
    /// outward sweep. An earlier build showed nothing at all in that case, which meant most people
    /// never saw the processing crest — a model needs three prior takes before it can be predicted
    /// from. An honest indeterminate sweep beats an empty screen; it just does not get to claim a
    /// duration, which is why the caption's countdown stays absent.
    private var progress: Double? {
        switch phase {
        case .live: return nil
        case .settled: return 1
        case .replay:
            if reduceMotion, !estimate.hasEstimate { return 1 }
            return estimate.hasEstimate ? estimate.progress : meter.indeterminateSweep
        }
    }

    var body: some View {
        GeometryReader { geo in
            let height = geometry.crestExtent + 40

            AmbientVoiceCrest(
                // Reduce Motion turns the crest into a static band. A light rippling across the
                // whole display is exactly the motion that setting exists to switch off.
                samples: reduceMotion ? [] : (phase == .live ? meter.trace : meter.replayEnvelope),
                tint: tint,
                core: palette.crestCore(for: state),
                intensity: state.intensity,
                palette: palette,
                notchDrop: geometry.hasNotch ? geometry.notchHeight : 0,
                notchWidth: geometry.notchWidth,
                baseDepth: geometry.crestBaseDepth * palette.bandScale,
                peakDepth: geometry.crestPeakDepth * palette.bandScale,
                progress: progress
            )
            .frame(width: geo.size.width, height: height)
            .position(x: geo.size.width / 2, y: height / 2)
            // The sweep is pushed from a task at ~12Hz. Interpolating between those pushes is the
            // difference between a travelling light and a row of jumps.
            .animation(reduceMotion ? nil : .linear(duration: 0.1), value: progress)
        }
        .allowsHitTesting(false)
    }
}

/// The running clock, split out so 10Hz ticks do not invalidate the take bar's neighbours.
struct AmbientTakeClock: View {
    let meter: AmbientMeter
    let palette: AmbientPalette

    var body: some View {
        Text(clock)
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(palette.textPrimary.opacity(0.9))
    }

    private var clock: String {
        let total = Int(meter.elapsed.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
