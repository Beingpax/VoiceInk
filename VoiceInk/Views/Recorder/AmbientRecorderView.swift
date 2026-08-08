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

    var color: Color {
        switch self {
        case .hidden: return .clear
        case .problem: return AppTheme.Recorder.healthBad
        case .working: return AppTheme.Status.warningStrong
        case .listening: return AppTheme.Recorder.healthOK
        }
    }
}

struct AmbientRecorderView<S: RecorderStateProvider & Observable>: View {
    var stateProvider: S
    var recorder: Recorder

    @State private var healthMonitor = RecorderInputHealthMonitor()
    @State private var level: Double = 0

    /// Border thickness at silence and at full level. The screen edge breathes with your voice —
    /// the most direct "it can hear me" the app can give without drawing anything.
    private let minThickness: CGFloat = 2
    private let maxThickness: CGFloat = 9

    private var state: AmbientState {
        AmbientState.resolve(
            recordingState: stateProvider.recordingState,
            health: healthMonitor.health
        )
    }

    /// Damped hard, and flattened entirely under Reduce Motion: a full-screen border pulsing with
    /// audio is close to a migraine trigger.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var thickness: CGFloat {
        guard state != .hidden else { return 0 }
        guard !reduceMotion else { return (minThickness + maxThickness) / 2 }
        return minThickness + (maxThickness - minThickness) * CGFloat(level)
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
            .animation(.easeOut(duration: 0.12), value: thickness)
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

    private var frame: some View {
        Rectangle()
            .strokeBorder(
                LinearGradient(
                    colors: [state.color.opacity(0.95), state.color.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: thickness
            )
            .shadow(color: state.color.opacity(0.45), radius: thickness * 1.6)
    }

    /// A light completing one lap of the perimeter, where the lap *is* the predicted wait.
    /// Distance travelled is time remaining — progress becomes a physical quantity.
    private func perimeterProgress(in size: CGSize) -> some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            let position = seconds.truncatingRemainder(dividingBy: 3) / 3

            Rectangle()
                .stroke(state.color, lineWidth: max(thickness, 3))
                .mask(
                    Rectangle()
                        .trim(from: position, to: min(position + 0.16, 1))
                        .stroke(style: StrokeStyle(lineWidth: max(thickness, 3) * 2))
                )
                .blur(radius: 1.5)
        }
        .frame(width: size.width, height: size.height)
    }
}
