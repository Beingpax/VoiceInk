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

struct AmbientRecorderView<S: RecorderStateProvider & Observable>: View {
    /// Arriving should feel immediate — it is feedback that a key press worked. Leaving should not:
    /// nothing is urgent about the light going away, and a quick cut reads as a glitch.
    /// Every change of stage is a plain cross-dissolve, quick in both directions. Scale and offset
    /// were doing too much: at this size a caption that also grows and slides reads as busy, and
    /// the point of the surface is that state changes register without demanding attention.
    private static var fadeIn: Animation { .easeOut(duration: 0.18) }
    private static var fadeOut: Animation { .easeInOut(duration: 0.24) }

    var stateProvider: S
    var recorder: Recorder

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AmbientBackgroundMode.userDefaultsKey) private var backgroundMode =
        AmbientBackgroundMode.auto.rawValue
    @AppStorage(RecorderDisplaySettingsKeys.showLiveTranscript) private var showLiveTranscript = true

    private var palette: AmbientPalette {
        .resolve(colorScheme, mode: AmbientBackgroundMode(rawValue: backgroundMode) ?? .auto)
    }
    private var stateColor: Color { palette.color(for: state) }

    @State private var healthMonitor = RecorderInputHealthMonitor()
    @State private var silenceWatch = RecorderSilenceWatch()
    @State private var level: Double = 0
    @State private var hasShownContextForTake = false
    @State private var takeStartedAt: Date?
    /// Rolling voice history for the crest. ~2s at the 30Hz sample rate below.
    @State private var trace: [Double] = []
    /// The whole take, kept so the crest can replay it while it is being transcribed.
    @State private var takeSamples: [Double] = []
    @State private var takeEnvelope: [Double] = []
    @State private var processingEstimate = RecorderProcessingEstimate()
    @State private var indeterminateSweep: Double = 0
    @State private var elapsed: TimeInterval = 0

    /// Width of the light band at silence and at full level. Most of the band is positioned
    /// off-screen, so what you actually see is its inward falloff — light seeping in from the
    /// bezel rather than a line drawn on top of your work.
    private let minBloom: CGFloat = 30
    private let maxBloom: CGFloat = 78

    /// Depth of the top-edge crest at rest and at full voice. The resting depth is what the crest
    /// hands off to the side edges at the corners, so it is deliberately close to `minBloom`.
    private let crestBaseDepth: CGFloat = 24
    private let crestPeakDepth: CGFloat = 52

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

    /// The edge wash steps back when the notch is carrying the signal — but only a little. At the
    /// old 0.35 the edges were three times dimmer than the crest, and the two stopped reading as
    /// the same light.
    private var edgeIntensity: Double {
        hasNotch ? state.intensity * 0.62 : state.intensity
    }

    /// How far below the hardware edge the crest can reach at full voice. Everything that has to
    /// sit clear of the light measures from here.
    private var crestExtent: CGFloat {
        (hasNotch ? notchHeight : 0) + crestBaseDepth + crestPeakDepth
    }

    /// macOS does not expose the display's physical corner radius. A squared-off glow fights the
    /// rounded corners badly, and this is close enough that the light appears to hug the bezel.
    private var displayCornerRadius: CGFloat {
        (NSScreen.main?.safeAreaInsets.top ?? 0) > 0 ? 12 : 8
    }

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
                hasTake: hasTake
            )
        )
    }

    private var state: AmbientState { presentation.state }
    private var crestPhase: AmbientCrestPhase? { presentation.crestPhase }

    /// Damped hard, and flattened entirely under Reduce Motion: a full-screen border pulsing with
    /// audio is close to a migraine trigger.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Quantised to 3pt steps on purpose. This drives a blurred stroke the size of the display,
    /// which is the most expensive thing drawn here, and at 30Hz it was being re-rendered for
    /// changes far below the threshold of sight. Snapping to steps cuts those re-renders by roughly
    /// an order of magnitude and looks identical.
    private var bloomWidth: CGFloat {
        guard state != .hidden else { return 0 }
        guard !reduceMotion else { return (minBloom + maxBloom) / 2 }
        let exact = minBloom + (maxBloom - minBloom) * CGFloat(level)
        return (exact / 3).rounded() * 3
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if state != .hidden {
                    frame
                        .transition(.opacity)
                        .allowsHitTesting(false)

                    Group {
                        if hasNotch {
                            notchGlow(in: geo.size)
                        } else if state == .working, crestPhase == nil {
                            perimeterProgress(in: geo.size)
                        }

                        if let crestPhase {
                            voiceCrest(in: geo.size, phase: crestPhase)
                                .id(crestPhase)
                                .transition(.opacity)
                        }
                    }
                    .allowsHitTesting(false)
                }

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
                        // Identity per kind, so a change of kind is an insert plus a remove — the
                        // two overlap and dissolve. Without this SwiftUI keeps one view and swaps
                        // its contents, and the text pops while the bloom jumps to its new size.
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
                                elapsed: elapsed,
                                isEnhancementEnabled: isEnhancementEnabled,
                                deviceName: healthMonitor.health.isProblem
                                    ? AudioDeviceManager.shared.currentInputDeviceName : nil,
                                tint: stateColor,
                                palette: palette,
                                onCancel: { Task { await stateProvider.cancelTakeFromPanel() } }
                            )
                        }
                        .ambientTextBloom(
                            tint: stateColor, fill: palette.bloomFill, opacity: 0.78
                        )
                        .fixedSize()
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, captionY)
            }
            .animation(.easeOut(duration: 0.14), value: bloomWidth)
            .animation(state == .hidden ? Self.fadeOut : Self.fadeIn, value: state)
            .animation(caption == nil ? Self.fadeOut : Self.fadeIn, value: captionIdentity)
            .animation(Self.fadeIn, value: stateProvider.recordingState)
        }
        .ignoresSafeArea()
        .task(id: stateProvider.recordingState) {
            let recordingState = stateProvider.recordingState

            if recordingState == .transcribing || recordingState == .enhancing {
                // Fold the take down once, here, rather than every frame in the Canvas.
                if takeEnvelope.isEmpty {
                    takeEnvelope = AmbientTakeEnvelope.downsample(takeSamples, to: 110)
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
                    indeterminateSweep =
                        Date().timeIntervalSince(startedAt)
                        .truncatingRemainder(dividingBy: 0.5) / 0.5
                    try? await Task.sleep(for: .milliseconds(80))
                }
                return
            }

            processingEstimate.end()

            guard recordingState == .recording else {
                healthMonitor.reset()
                level = 0
                return
            }
            hasShownContextForTake = false
            takeStartedAt = .now
            elapsed = 0
            trace = []
            takeSamples = []
            takeEnvelope = []
            var tick = 0

            while !Task.isCancelled {
                let meter = recorder.audioMeterSnapshot()

                trace.append(meter.averagePower)
                if trace.count > 64 { trace.removeFirst() }

                tick += 1
                // Every third tick: the monitor's windows are counted in samples and calibrated at
                // 10Hz, so it must keep seeing that rate.
                guard tick % 3 == 0 else {
                    try? await Task.sleep(for: .milliseconds(33))
                    continue
                }

                healthMonitor.ingest(meter)
                // Decimated to the same 10Hz the monitor sees: a minute of speech is 600 values,
                // and the envelope is folded to a fixed size anyway.
                takeSamples.append(meter.averagePower)

                if silenceWatch.ingest(isSilent: healthMonitor.health == .silent) {
                    await stateProvider.stopTakeFromPanel()
                    return
                }

                // The context line is an acknowledgement, not a status field — it says its piece
                // at the start of the take and then gets out of the way.
                elapsed = Date().timeIntervalSince(takeStartedAt ?? .now)

                if !hasShownContextForTake, contextMessage != nil,
                    Date().timeIntervalSince(takeStartedAt ?? .now) > 3
                {
                    hasShownContextForTake = true
                }
                // Damped: track rises quickly, fall back slowly, so the border does not strobe.
                let target = meter.averagePower
                level = target > level ? level * 0.5 + target * 0.5 : level * 0.85 + target * 0.15
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    /// Spans the whole display. The crest *is* the top edge of the frame, so it has to run corner
    /// to corner and arrive at both of them at the same depth as the side wash.
    private func voiceCrest(in size: CGSize, phase: AmbientCrestPhase) -> some View {
        let progress: Double? =
            switch phase {
            case .live: nil
            case .replay: motionlessCrest && !processingEstimate.hasEstimate ? 1 : processingSweep
            case .settled: 1
            }

        return AmbientVoiceCrest(
            samples: motionlessCrest ? [] : (phase == .live ? trace : replayEnvelope),
            tint: stateColor,
            intensity: state.intensity,
            palette: palette,
            notchDrop: hasNotch ? notchHeight : 0,
            notchWidth: notchWidth,
            baseDepth: crestBaseDepth,
            peakDepth: crestPeakDepth,
            progress: progress
        )
        .frame(width: size.width, height: crestExtent + 40)
        .position(x: size.width / 2, y: (crestExtent + 40) / 2)
        // The sweep is pushed from a task at ~12Hz. Interpolating between those pushes is the
        // difference between a travelling light and a row of jumps.
        .animation(motionlessCrest ? nil : .linear(duration: 0.1), value: progress)
    }

    /// Deliberately measured against a *typical* crest rather than its maximum reach. Clearing the
    /// loudest possible moment left a gap of dead screen most of the time and the caption floated
    /// unattached; sitting where the light usually ends means a loud passage laps over the top of
    /// the words, which reads as the text being inside the glow rather than beneath it.
    private var captionY: CGFloat {
        (hasNotch ? notchHeight : 0) + crestBaseDepth + crestPeakDepth * 0.42 + 12
    }

    private var hasTake: Bool { takeEnvelope.count > 2 || takeSamples.count > 2 }

    /// The processing task fills `takeEnvelope` a frame after the state flips. Folding inline for
    /// that one frame is what stops the crest blinking out and back on every take.
    private var replayEnvelope: [Double] {
        takeEnvelope.isEmpty
            ? AmbientTakeEnvelope.downsample(takeSamples, to: 110)
            : takeEnvelope
    }

    /// How far out the replay has travelled.
    ///
    /// With history behind it this is the real predicted progress. Without, it is a repeating
    /// outward sweep — the earlier build showed nothing at all in that case, which meant most
    /// people never saw the processing crest, because a model needs three prior takes before it
    /// can be predicted from. An honest indeterminate sweep beats an empty screen; it just does
    /// not get to claim a duration, which is why the caption's countdown stays absent.
    private var processingSweep: Double {
        processingEstimate.hasEstimate ? processingEstimate.progress : indeterminateSweep
    }

    /// Reduce Motion turns the crest into a static band and stops the sweep travelling. A light
    /// rippling across the whole display is exactly the kind of motion that setting exists to
    /// switch off, and the sweep still communicates without animating.
    private var motionlessCrest: Bool { reduceMotion }

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
    /// grow-out-of-the-notch animation.
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

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: displayCornerRadius, style: .continuous)
    }

    /// Two layers: a wide, heavily blurred band pushed half off-screen so only its falloff is
    /// visible, and a faint crisp line right at the bezel to give the light an origin. A single
    /// hard-edged stroke — which is what this was — reads as a rendering error rather than a glow.
    private var frame: some View {
        ZStack {
            // Borrowed darkness, for grounds that cannot carry a glow. See AmbientPalette.
            if palette.vignette > 0 {
                shape
                    .stroke(
                        Color.black.opacity(palette.vignette * edgeIntensity),
                        lineWidth: bloomWidth * 1.2
                    )
                    .blur(radius: bloomWidth * 0.55)
                    .padding(-bloomWidth / 2)
            }

            shape
                .stroke(stateColor.opacity(0.85 * edgeIntensity), lineWidth: bloomWidth)
                .blur(radius: bloomWidth * 0.5)
                .padding(-bloomWidth / 2)

            shape
                .stroke(stateColor.opacity(0.5 * edgeIntensity), lineWidth: 1)
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
            if palette.vignette > 0 {
                shape
                    .stroke(
                        Color.black.opacity(palette.vignette * state.intensity),
                        lineWidth: notchHalo * 1.3
                    )
                    .blur(radius: notchHalo * 0.8)
            }

            // Soft bloom bleeding outward from the cutout edge.
            shape
                .stroke(stateColor.opacity(0.45 * state.intensity), lineWidth: notchHalo)
                .blur(radius: notchHalo * 0.7)

            // Crisp contour so the halo has a defined source, kept faint — at full strength it
            // outlined the cutout like a sticker instead of lighting it.
            shape
                .stroke(stateColor.opacity(0.40 * state.intensity), lineWidth: 1)
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
                                stateColor.opacity(0.75),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .blur(radius: 5)

                        shape
                            .trim(from: position, to: min(position + 0.07, 1))
                            .stroke(stateColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
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
                        stateColor.opacity(0.7),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .blur(radius: 9)

                shape
                    .trim(from: position, to: min(position + 0.05, 1))
                    .stroke(
                        stateColor,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .blur(radius: 1.2)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}
