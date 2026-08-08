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
    @State private var silenceWatch = RecorderSilenceWatch()
    @State private var level: Double = 0
    @State private var hasShownContextForTake = false
    @State private var takeStartedAt: Date?

    /// Width of the light band at silence and at full level. Most of the band is positioned
    /// off-screen, so what you actually see is its inward falloff — light seeping in from the
    /// bezel rather than a line drawn on top of your work.
    private let minBloom: CGFloat = 26
    private let maxBloom: CGFloat = 62

    /// On a notched Mac the eye already goes to the cutout, so that becomes the focal point and
    /// the screen edge drops back to a supporting wash. Lighting the whole perimeter equally on a
    /// display that has a notch wastes the one place the user is already looking.
    private var hasNotch: Bool {
        (NSScreen.main?.safeAreaInsets.top ?? 0) > 0
    }

    private var notchWidth: CGFloat {
        guard let screen = NSScreen.main else { return 180 }
        if let left = screen.auxiliaryTopLeftArea?.width,
            let right = screen.auxiliaryTopRightArea?.width
        {
            return screen.frame.width - left - right
        }
        return 180
    }

    private var notchHeight: CGFloat {
        guard let screen = NSScreen.main else { return 37 }
        if screen.safeAreaInsets.top > 0 { return screen.safeAreaInsets.top }
        return NSApplication.shared.mainMenu?.menuBarHeight ?? NSStatusBar.system.thickness
    }

    /// Halo width around the cutout. Smaller range than the screen edge — the notch is a much
    /// tighter object and the same 62pt bloom would swallow it.
    private var notchHalo: CGFloat {
        guard state != .hidden else { return 0 }
        guard !reduceMotion else { return 11 }
        return 6 + 11 * CGFloat(level)
    }

    /// The edge wash steps back when the notch is carrying the signal.
    private var edgeIntensity: Double {
        hasNotch ? state.intensity * 0.35 : state.intensity
    }

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
                        .allowsHitTesting(false)

                    Group {
                        if hasNotch {
                            notchGlow(in: geo.size)
                        } else if state == .working {
                            perimeterProgress(in: geo.size)
                        }
                    }
                    .allowsHitTesting(false)
                }

                if let caption {
                    AmbientCaption(
                        kind: caption,
                        tint: captionTint,
                        onUndo: { Task { await stateProvider.undoResultPeek() } },
                        onRetry: { stateProvider.retryResultPeek() },
                        onKeepRecording: { silenceWatch.reset() }
                    )
                    .position(x: geo.size.width / 2, y: captionY)
                    // Grows out of the notch rather than opening like a window.
                    .transition(
                        .scale(scale: 0.86, anchor: .top)
                            .combined(with: .opacity)
                            .combined(with: .offset(y: -10))
                    )
                }
            }
            .animation(.easeOut(duration: 0.14), value: bloomWidth)
            .animation(AppTheme.Motion.standard, value: state)
            .animation(AppTheme.Motion.standard, value: caption)
        }
        .ignoresSafeArea()
        .task(id: stateProvider.recordingState) {
            guard stateProvider.recordingState == .recording else {
                healthMonitor.reset()
                level = 0
                return
            }
            hasShownContextForTake = false
            takeStartedAt = .now

            while !Task.isCancelled {
                let meter = recorder.audioMeterSnapshot()
                healthMonitor.ingest(meter)

                if silenceWatch.ingest(isSilent: healthMonitor.health == .silent) {
                    await stateProvider.stopTakeFromPanel()
                    return
                }

                // The context line is an acknowledgement, not a status field — it says its piece
                // at the start of the take and then gets out of the way.
                if !hasShownContextForTake, contextMessage != nil,
                    Date().timeIntervalSince(takeStartedAt ?? .now) > 3
                {
                    hasShownContextForTake = true
                }
                // Damped: track rises quickly, fall back slowly, so the border does not strobe.
                let target = meter.averagePower
                level = target > level ? level * 0.5 + target * 0.5 : level * 0.85 + target * 0.15
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// Sits just below the cutout, or below the menu bar on a display without one.
    private var captionY: CGFloat {
        (hasNotch ? notchHeight : 24) + 46
    }

    private var captionTint: Color {
        state == .hidden ? AmbientState.working.color : state.color
    }

    /// Words only for the three cases light cannot carry, in priority order. Everything else stays
    /// wordless, which is what keeps the caption meaningful when it does appear.
    private var caption: AmbientCaptionKind? {
        if let peek = stateProvider.resultPeek {
            return .result(peek)
        }
        if let seconds = silenceWatch.secondsRemaining {
            return .countdown(seconds)
        }
        if stateProvider.recordingState == .recording, healthMonitor.health.isProblem,
            let label = healthMonitor.health.problemMessage
        {
            return .problem(label)
        }
        if stateProvider.recordingState == .recording, !hasShownContextForTake,
            let summary = contextMessage
        {
            return .context(summary)
        }
        return nil
    }

    /// Named explicitly rather than as chips: without a panel there is no room for a legend, so
    /// the sentence has to carry its own meaning.
    private var contextMessage: String? {
        let context = stateProvider.contextSummary
        guard !context.isEmpty else { return nil }

        var parts: [String] = []
        if let words = context.selectedWordCount {
            parts.append(String(format: String(localized: "selection · %lld words"), Int64(words)))
        }
        if context.hasScreenText { parts.append(String(localized: "screen")) }
        if context.hasClipboardText { parts.append(String(localized: "clipboard")) }
        guard !parts.isEmpty else { return nil }

        return String(format: String(localized: "Sending %@"), parts.joined(separator: " · "))
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
                .stroke(state.color.opacity(0.85 * edgeIntensity), lineWidth: bloomWidth)
                .blur(radius: bloomWidth * 0.5)
                .padding(-bloomWidth / 2)

            shape
                .stroke(state.color.opacity(0.5 * edgeIntensity), lineWidth: 1)
                .blur(radius: 0.5)
        }
    }

    /// Light spilling around the camera housing, hugging the cutout's own contour.
    ///
    /// This is the notch-appropriate form of the same idea: the border is still the instrument,
    /// but on a notched display the instrument is the notch. The cutout is physically black and
    /// unlit, so a halo around it reads as the hardware itself glowing — which the screen edge
    /// cannot do, because it has content behind it.
    private func notchGlow(in size: CGSize) -> some View {
        let shape = NotchShape(topCornerRadius: 6, bottomCornerRadius: 13)
        let width = notchWidth
        let height = notchHeight

        return ZStack {
            // Soft bloom bleeding outward from the cutout edge.
            shape
                .stroke(state.color.opacity(0.45 * state.intensity), lineWidth: notchHalo)
                .blur(radius: notchHalo * 0.7)

            // Crisp contour so the halo has a defined source, kept faint — at full strength it
            // outlined the cutout like a sticker instead of lighting it.
            shape
                .stroke(state.color.opacity(0.40 * state.intensity), lineWidth: 1)
                .blur(radius: 0.8)

            // Progress laps the cutout rather than the whole screen — a far shorter circuit, so
            // the same duration reads as a much more legible rate of travel.
            if state == .working {
                TimelineView(.animation(paused: reduceMotion)) { context in
                    let position =
                        context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 2.4) / 2.4

                    ZStack {
                        shape
                            .trim(from: position, to: min(position + 0.18, 1))
                            .stroke(
                                state.color.opacity(0.75),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .blur(radius: 5)

                        shape
                            .trim(from: position, to: min(position + 0.07, 1))
                            .stroke(state.color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .blur(radius: 0.8)
                    }
                }
            }
        }
        .frame(width: width, height: height)
        .position(x: size.width / 2, y: height / 2)
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
