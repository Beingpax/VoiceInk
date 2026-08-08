import SwiftUI

/// Ambient recorder — the display border *is* the instrument. No panel.
///
/// The governing rule is that **the frame never says two things at once**. Position carries no
/// meaning: an arbiter picks the single most important state and the whole border says only that,
/// so there is no legend to memorise and no edge whose meaning has to be learned.
///
/// Only two properties are ever in play — colour (what is happening) and thickness (how loud you
/// are). Progress is the one exception and uses motion instead of a third property.
enum AmbientState: Equatable {
    case hidden
    /// Highest priority: the input is failing.
    case problem
    /// Working — transcribing or enhancing.
    case working
    /// Listening, healthy.
    case listening

    /// One message at a time, chosen by priority rather than combined.
    static func resolve(
        recordingState: RecordingState,
        health: RecorderInputHealth
    ) -> AmbientState {
        switch recordingState {
        case .recording:
            return health.isProblem ? .problem : .listening
        case .transcribing, .enhancing:
            return .working
        case .idle, .starting, .busy:
            return .hidden
        }
    }

    /// Light, not UI colour. `systemGreen` and friends are tuned to sit inside controls against a
    /// known background; spread across a whole display edge they read as a coloured rectangle
    /// rather than something glowing. These are lighter and less saturated.
    var color: Color {
        switch self {
        case .hidden: return .clear
        case .problem: return Color(red: 0.97, green: 0.42, blue: 0.36)
        case .working: return Color(red: 0.98, green: 0.72, blue: 0.35)
        case .listening: return Color(red: 0.38, green: 0.86, blue: 0.68)
        }
    }

    /// The common case should be calm. A problem is allowed to be louder than "recording fine".
    var intensity: Double {
        switch self {
        case .hidden: return 0
        case .listening: return 0.55
        case .working: return 0.75
        case .problem: return 1.0
        }
    }
}

struct AmbientRecorderView<S: RecorderStateProvider & Observable>: View {
    var stateProvider: S
    var recorder: Recorder

    @State private var healthMonitor = RecorderInputHealthMonitor()
    @State private var level: Double = 0

    /// Width of the light band at silence and at full level. Most of the band is positioned
    /// off-screen, so what you actually see is its inward falloff — light seeping in from the
    /// bezel rather than a line drawn on top of your work.
    private let minBloom: CGFloat = 26
    private let maxBloom: CGFloat = 62

    /// macOS does not expose the display's physical corner radius. A squared-off glow fights the
    /// rounded corners badly, and this is close enough that the light appears to hug the bezel.
    private var displayCornerRadius: CGFloat {
        (NSScreen.main?.safeAreaInsets.top ?? 0) > 0 ? 12 : 8
    }

    private var state: AmbientState {
        AmbientState.resolve(
            recordingState: stateProvider.recordingState,
            health: healthMonitor.health
        )
    }

    /// Damped hard, and flattened entirely under Reduce Motion: a full-screen border pulsing with
    /// audio is close to a migraine trigger.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var bloomWidth: CGFloat {
        guard state != .hidden else { return 0 }
        guard !reduceMotion else { return (minBloom + maxBloom) / 2 }
        return minBloom + (maxBloom - minBloom) * CGFloat(level)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if state != .hidden {
                    frame
                    if state == .working {
                        perimeterProgress(in: geo.size)
                    }
                }
            }
            .animation(.easeOut(duration: 0.14), value: bloomWidth)
            .animation(AppTheme.Motion.standard, value: state)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .task(id: stateProvider.recordingState) {
            guard stateProvider.recordingState == .recording else {
                healthMonitor.reset()
                level = 0
                return
            }
            while !Task.isCancelled {
                let meter = recorder.audioMeterSnapshot()
                healthMonitor.ingest(meter)
                // Damped: track rises quickly, fall back slowly, so the border does not strobe.
                let target = meter.averagePower
                level = target > level ? level * 0.5 + target * 0.5 : level * 0.85 + target * 0.15
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: displayCornerRadius, style: .continuous)
    }

    /// Two layers: a wide, heavily blurred band pushed half off-screen so only its falloff is
    /// visible, and a faint crisp line right at the bezel to give the light an origin. A single
    /// hard-edged stroke — which is what this was — reads as a rendering error rather than a glow.
    private var frame: some View {
        ZStack {
            shape
                .stroke(state.color.opacity(0.85 * state.intensity), lineWidth: bloomWidth)
                .blur(radius: bloomWidth * 0.5)
                .padding(-bloomWidth / 2)

            shape
                .stroke(state.color.opacity(0.5 * state.intensity), lineWidth: 1)
                .blur(radius: 0.5)
        }
    }

    /// A light completing one lap of the perimeter, where the lap *is* the predicted wait.
    /// Distance travelled is time remaining — progress becomes a physical quantity.
    private func perimeterProgress(in size: CGSize) -> some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            let position = seconds.truncatingRemainder(dividingBy: 3) / 3

            // A comet running the perimeter: a soft wide tail with a brighter core, so it reads
            // as a moving light rather than a sliding rectangle segment.
            ZStack {
                shape
                    .trim(from: position, to: min(position + 0.14, 1))
                    .stroke(
                        state.color.opacity(0.7),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .blur(radius: 9)

                shape
                    .trim(from: position, to: min(position + 0.05, 1))
                    .stroke(
                        state.color,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .blur(radius: 1.2)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}
