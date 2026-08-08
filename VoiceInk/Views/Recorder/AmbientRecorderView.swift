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
    /// The take has landed and is being offered back. Not a working state — nothing is happening —
    /// but the light staying on is what keeps the result from reading as a stray tooltip on an
    /// otherwise dark screen.
    case settled

    // Colour lives in AmbientPalette, which has to answer differently on a light background, and
    // the priority arbiter lives in AmbientPresentation so it can be tested.

    /// The common case should be calm. A problem is allowed to be louder than "recording fine".
    var intensity: Double {
        switch self {
        case .hidden: return 0
        // Quieter than listening on purpose: the take is done, and this is an afterglow rather
        // than an instrument.
        case .settled: return 0.5
        case .listening: return 0.72
        case .working: return 0.88
        case .problem: return 1.0
        }
    }
}

/// Orchestrates the surface: runs the sampling loop, resolves what to show, and owns the text.
///
/// Deliberately reads **none** of the audio-rate state. Everything that moves at 30Hz lives on
/// `AmbientMeter` and is read only by the leaf that draws it, so this body evaluates when the
/// *stage* of a take changes rather than when the waveform does. See `AmbientMeter` for the
/// measurement that forced the split.
struct AmbientRecorderView<S: RecorderStateProvider & Observable>: View {
    /// Every change of stage is a plain cross-dissolve, quick in both directions. Scale and offset
    /// were doing too much: at this size a caption that also grows and slides reads as busy, and
    /// the point of the surface is that state changes register without demanding attention.
    private static var fadeIn: Animation { .easeOut(duration: 0.18) }
    private static var fadeOut: Animation { .easeInOut(duration: 0.24) }

    var stateProvider: S
    var recorder: Recorder
    /// Lets the window drop out of the event path entirely when nothing here is clickable.
    var onInteractiveChange: (Bool) -> Void = { _ in }

    @AppStorage(AmbientBackgroundMode.userDefaultsKey) private var backgroundMode =
        AmbientBackgroundMode.auto.rawValue
    @AppStorage(RecorderDisplaySettingsKeys.showLiveTranscript) private var showLiveTranscript = true

    @State private var meter = AmbientMeter()
    @State private var healthMonitor = RecorderInputHealthMonitor()
    @State private var silenceWatch = RecorderSilenceWatch()
    @State private var processingEstimate = RecorderProcessingEstimate()
    @State private var hasShownContextForTake = false
    @State private var takeStartedAt: Date?
    @State private var geometry = AmbientGeometry.current()
    @State private var background = AmbientBackgroundSensor()

    private var palette: AmbientPalette {
        .resolve(
            measuredLight: background.resolved,
            mode: AmbientBackgroundMode(rawValue: backgroundMode) ?? .auto
        )
    }

    private var stateColor: Color { palette.color(for: state) }

    private var presentation: AmbientPresentation {
        AmbientPresentation.resolve(
            AmbientInputs(
                recordingState: stateProvider.recordingState,
                health: healthMonitor.health,
                hasResultPeek: stateProvider.resultPeek != nil,
                silenceCountdown: silenceWatch.secondsRemaining,
                hasLiveTranscript: showLiveTranscript
                    && !stateProvider.partialTranscript.isEmpty,
                hasContextMessage: contextMessage != nil,
                hasShownContext: hasShownContextForTake,
                hasTake: meter.hasTake
            )
        )
    }

    private var state: AmbientState { presentation.state }

    /// The only three moments this surface has anything to click: the result peek's buttons, the
    /// silence countdown's reprieve, and the mode strip and cancel shown during a take.
    private var isInteractive: Bool {
        stateProvider.resultPeek != nil
            || silenceWatch.secondsRemaining != nil
            || stateProvider.recordingState == .recording
    }

    var body: some View {
        ZStack {
            if state != .hidden {
                AmbientFrameLayer(
                    meter: meter,
                    state: state,
                    geometry: geometry,
                    palette: palette,
                    tint: stateColor,
                    showsPerimeterProgress: state == .working && presentation.crestPhase == nil
                )
                .transition(.opacity)

                if let phase = presentation.crestPhase {
                    AmbientCrestLayer(
                        meter: meter,
                        phase: phase,
                        state: state,
                        geometry: geometry,
                        palette: palette,
                        tint: stateColor,
                        estimate: processingEstimate
                    )
                    // Identity per phase, so each boundary is an insert plus a remove and the two
                    // dissolve. The sample array is swapped wholesale between phases and an array
                    // cannot be interpolated, so without this the shape snaps.
                    .id(phase)
                    .transition(.opacity)
                }
            }

            words
        }
        .ignoresSafeArea()
        .animation(state == .hidden ? Self.fadeOut : Self.fadeIn, value: state)
        .animation(caption == nil ? Self.fadeOut : Self.fadeIn, value: captionIdentity)
        .animation(Self.fadeIn, value: stateProvider.recordingState)
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didChangeScreenParametersNotification)
        ) { _ in
            geometry = .current()
        }
        .task(id: stateProvider.recordingState) { await run() }
        .onChange(of: isInteractive, initial: true) { _, value in onInteractiveChange(value) }
        .onDisappear { onInteractiveChange(false) }
    }

    // MARK: - Text

    private var words: some View {
        VStack(spacing: 12) {
            if let caption {
                AmbientCaption(
                    kind: caption,
                    tint: captionTint,
                    palette: palette,
                    onUndo: { Task { await stateProvider.undoResultPeek() } },
                    onRetry: { stateProvider.retryResultPeek() },
                    onKeepRecording: { silenceWatch.reset() }
                )
                // Identity per kind, so a change of kind is an insert plus a remove — the two
                // overlap and dissolve. Without this SwiftUI keeps one view and swaps its
                // contents, and the text pops while the bloom jumps to its new size.
                .id(captionIdentity)
                .transition(.opacity)
            }

            if stateProvider.recordingState == .recording {
                HStack(spacing: 16) {
                    AmbientModeStrip(tint: stateColor, palette: palette)

                    Rectangle()
                        .fill(palette.separator.opacity(0.7))
                        .frame(width: 1, height: 13)

                    AmbientTakeBar(
                        clock: { AmbientTakeClock(meter: meter, palette: palette) },
                        isEnhancementEnabled: isEnhancementEnabled,
                        deviceName: healthMonitor.health.isProblem
                            ? AudioDeviceManager.shared.currentInputDeviceName : nil,
                        tint: stateColor,
                        palette: palette,
                        onCancel: { Task { await stateProvider.cancelTakeFromPanel() } }
                    )
                }
                .ambientTextBloom(
                    tint: stateColor, fill: palette.bloomFill,
                    opacity: palette.isLight ? 0.85 : 0.62
                )
                .fixedSize()
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, geometry.captionY)
    }

    // MARK: - The take

    private func run() async {
        let recordingState = stateProvider.recordingState

        if recordingState == .transcribing || recordingState == .enhancing {
            // Fold the take down once, here, rather than every frame in the Canvas.
            if meter.takeEnvelope.isEmpty {
                meter.takeEnvelope = AmbientTakeEnvelope.downsample(meter.takeSamples, to: 110)
            }
            if !processingEstimate.hasEstimate {
                processingEstimate.begin(
                    audioDuration: stateProvider.lastTakeAudioDuration,
                    modelName: stateProvider.activeTranscriptionModelName
                )
            }
            let startedAt = Date()
            while !Task.isCancelled {
                processingEstimate.tick()
                // Only consulted when there is no prediction to sweep by.
                meter.indeterminateSweep =
                    Date().timeIntervalSince(startedAt)
                    .truncatingRemainder(dividingBy: 0.5) / 0.5
                try? await Task.sleep(for: .milliseconds(80))
            }
            return
        }

        processingEstimate.end()

        guard recordingState == .recording else {
            healthMonitor.reset()
            meter.endTake()
            return
        }

        hasShownContextForTake = false
        takeStartedAt = .now
        // Without this a silence carried over from the last take can stop this one immediately.
        silenceWatch.reset()
        meter.beginTake()
        geometry = .current()
        // Once per take, off the main path. The window it lands in is the one the light will spend
        // the take sitting on.
        background.sample()
        var tick = 0

        while !Task.isCancelled {
            let sample = recorder.audioMeterSnapshot()
            meter.append(sample.averagePower)

            tick += 1
            // Every third tick: the monitor's windows are counted in samples and calibrated at
            // 10Hz, so it must keep seeing that rate.
            guard tick % 3 == 0 else {
                try? await Task.sleep(for: .milliseconds(33))
                continue
            }

            healthMonitor.ingest(sample)
            // Decimated to the same 10Hz the monitor sees: a minute of speech is 600 values, and
            // the envelope is folded to a fixed size anyway.
            meter.recordTakeSample(sample.averagePower)

            if silenceWatch.ingest(isSilent: healthMonitor.isQuiet) {
                await stateProvider.stopTakeFromPanel()
                return
            }

            meter.elapsed = Date().timeIntervalSince(takeStartedAt ?? .now)

            // The context line is an acknowledgement, not a status field — it says its piece at
            // the start of the take and then gets out of the way.
            if !hasShownContextForTake, contextMessage != nil, meter.elapsed > 3 {
                hasShownContextForTake = true
            }

            // Damped: rises quickly, falls back slowly, so the border does not strobe.
            let target = sample.averagePower
            meter.level =
                target > meter.level
                ? meter.level * 0.5 + target * 0.5
                : meter.level * 0.85 + target * 0.15

            try? await Task.sleep(for: .milliseconds(33))
        }
    }

    // MARK: - Captions

    private var isEnhancementEnabled: Bool {
        ModeManager.shared.currentEffectiveConfiguration?.isAIEnhancementEnabled ?? false
    }

    private var captionTint: Color {
        state == .hidden ? palette.color(for: .working) : stateColor
    }

    /// Words only for the cases light cannot carry. Which one wins is decided by
    /// `AmbientPresentation`; this only supplies the payload.
    private var caption: AmbientCaptionKind? {
        switch presentation.captionSlot {
        case .none:
            return nil
        case .result:
            return stateProvider.resultPeek.map { .result($0) }
        case .processing:
            return .processing(
                title: stateProvider.recordingState == .enhancing ? "Enhancing" : "Transcribing",
                remaining: processingEstimate.remaining,
                basis: processingEstimate.basis
            )
        case .countdown:
            return silenceWatch.secondsRemaining.map { .countdown($0) }
        case .problem:
            return healthMonitor.health.problemMessage.map { .problem($0) }
        case .context:
            return contextMessage.map { .context($0) }
        case .liveTranscript:
            return .liveTranscript(stateProvider.partialTranscript)
        }
    }

    /// What kind of caption is showing, ignoring its contents. The container transition animates on
    /// this rather than on `caption` — otherwise every word of the live transcript would re-run the
    /// insertion animation.
    private var captionIdentity: Int {
        switch caption {
        case .none: return 0
        case .result: return 1
        case .countdown: return 2
        case .problem: return 3
        case .context: return 4
        case .liveTranscript: return 5
        case .processing: return 6
        }
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
}
