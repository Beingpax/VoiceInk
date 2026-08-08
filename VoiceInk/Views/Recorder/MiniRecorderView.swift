import SwiftUI

struct MiniRecorderView<S: RecorderStateProvider & Observable>: View {
    var stateProvider: S
    var recorder: Recorder
    var assistantSession: AssistantSession
    let onRecordButtonTapped: () -> Void
    let onCloseTapped: () -> Void
    let onAssistantFollowUp: (String) -> Void
    @AppStorage(RecorderDisplaySettingsKeys.showLiveTranscript) private var showLiveTranscript = true
    @State private var healthMonitor = RecorderInputHealthMonitor()
    @State private var densityJudge = RecorderDensityJudge()
    @State private var isModeRowExpanded = false
    @State private var processingEstimate = RecorderProcessingEstimate()
    @State private var silenceWatch = RecorderSilenceWatch()
    @State private var dragOffset: CGFloat = 0

    // MARK: - Layout Constants

    private let controlBarHeight: CGFloat = 40
    private let compactCornerRadius: CGFloat = 20
    private let expandedCornerRadius: CGFloat = 14

    /// The mode row needs room the compact width does not have, so an open row widens the panel
    /// without disturbing the width grammar for every other state.
    private func panelWidth(for presentation: RecorderPresentation) -> CGFloat {
        let base = width(for: presentation.widthClass)
        guard isModeRowExpanded else { return base }
        // Four chips at ~86pt each plus the record button and padding. 330 clipped the last two.
        return max(base, 470)
    }

    /// Width grammar — each width means exactly one thing.
    private func width(for widthClass: RecorderWidthClass) -> CGFloat {
        switch widthClass {
        case .compact: return 184
        case .standard: return 232
        case .wide: return 300
        case .conversation: return 520
        }
    }

    private var presentation: RecorderPresentation {
        RecorderPresentation(
            recordingState: stateProvider.recordingState,
            partialTranscript: stateProvider.partialTranscript,
            showLiveTranscript: showLiveTranscript,
            isAssistantVisible: assistantSession.isVisible,
            isAssistantBusy: assistantSession.isBusy,
            hasResultPeek: stateProvider.resultPeek != nil
        )
    }

    private var isExpanded: Bool {
        presentation.hasLiveTranscript || presentation.isAssistantVisible
    }

    var body: some View {
        let presentation = self.presentation

        VStack(spacing: 0) {
            if presentation.isAssistantVisible {
                AssistantPanelView(
                    session: assistantSession,
                    liveFollowUpText: presentation.assistantFollowUpText,
                    onSend: onAssistantFollowUp
                )
                separator
            } else if presentation.displayState == .result {
                resultPeekPanel
                separator
            } else if isProcessing, processingEstimate.hasEstimate {
                RecorderProcessingRow(state: presentation.recordingState, estimate: processingEstimate)
                separator
            } else if presentation.hasLiveTranscript {
                LiveTranscriptView(text: presentation.partialTranscript)
                separator
            }

            controlBar(presentation)

            if showsSignalStrip {
                RecorderSignalStrip(
                    health: healthMonitor.health,
                    context: stateProvider.contextSummary,
                    deviceName: AudioDeviceManager.shared.currentInputDeviceName,
                    silenceCountdown: silenceWatch.secondsRemaining,
                    onKeepRecording: { silenceWatch.reset() }
                )
            }
        }
        .frame(width: panelWidth(for: presentation))
        .background(
            RecorderChrome(
                cornerRadius: isExpanded ? expandedCornerRadius : compactCornerRadius,
                rimState: presentation.rimState
            )
        )
        .offset(x: dragOffset)
        .opacity(1 - min(abs(dragOffset) / cancelDragDistance, 1) * 0.55)
        .gesture(cancelDragGesture(isRecording: presentation.recordingState == .recording))
        .animation(AppTheme.Motion.standard, value: presentation.displayState)
        .animation(AppTheme.Motion.quick, value: isModeRowExpanded)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .task(id: presentation.recordingState) {
            let state = presentation.recordingState
            if state == .transcribing || state == .enhancing {
                if !processingEstimate.hasEstimate {
                    processingEstimate.begin(
                        audioDuration: stateProvider.lastTakeAudioDuration,
                        modelName: stateProvider.activeTranscriptionModelName
                    )
                }
                while !Task.isCancelled {
                    processingEstimate.tick()
                    try? await Task.sleep(for: .milliseconds(200))
                }
                return
            }

            processingEstimate.end()

            guard state == .recording else {
                healthMonitor.reset()
                densityJudge.endTake()
                silenceWatch.reset()
                return
            }
            // 10Hz sampling, scoped to the take and cancelled with it.
            RecorderModeFamiliarity.recordUse(of: ModeManager.shared.currentEffectiveConfiguration?.id)

            while !Task.isCancelled {
                healthMonitor.ingest(recorder.audioMeterSnapshot())
                judgeDensity()

                if silenceWatch.ingest(isSilent: healthMonitor.health == .silent) {
                    await stateProvider.stopTakeFromPanel()
                    return
                }

                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// How far the pill must travel before the take is abandoned.
    private let cancelDragDistance: CGFloat = 90

    /// Drag the pill sideways to abandon the take — the gesture messaging apps already taught
    /// everyone, replacing a double-press of Escape that nothing on screen advertised.
    /// Resistance grows with distance so the pill visibly fights back, which is what makes the
    /// gesture discoverable by accident.
    private func cancelDragGesture(isRecording: Bool) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard isRecording else { return }
                let raw = value.translation.width
                dragOffset = raw.sign == .minus
                    ? -sqrt(abs(raw)) * 7 : sqrt(raw) * 7
            }
            .onEnded { _ in
                let shouldCancel = abs(dragOffset) >= cancelDragDistance
                withAnimation(AppTheme.Motion.quick) { dragOffset = 0 }
                guard shouldCancel else { return }
                Task { await stateProvider.cancelTakeFromPanel() }
            }
    }

    private var isProcessing: Bool {
        presentation.recordingState == .transcribing || presentation.recordingState == .enhancing
    }

    /// The strip earns its space only when it has something non-obvious to report.
    private var showsSignalStrip: Bool {
        presentation.recordingState == .recording
            && densityJudge.density >= .standard
            && RecorderSignalStrip.shouldRender(
                health: healthMonitor.health,
                context: stateProvider.contextSummary,
                silenceCountdown: silenceWatch.secondsRemaining
            )
    }

    private func judgeDensity() {
        let mode = ModeManager.shared.currentEffectiveConfiguration
        densityJudge.evaluate(
            .init(
                isRecording: presentation.recordingState == .recording,
                hasHealthProblem: healthMonitor.health.isProblem,
                contextIsEmpty: stateProvider.contextSummary.isEmpty,
                isRealtimeTranscriptionEnabled: mode?.isRealtimeTranscriptionEnabled ?? false,
                showLiveTranscript: showLiveTranscript,
                isUnfamiliarMode: RecorderModeFamiliarity.isUnfamiliar(mode?.id),
                deviceChangedDuringTake: false
            )
        )
    }


    @ViewBuilder
    private var resultPeekPanel: some View {
        if let peek = stateProvider.resultPeek {
            RecorderResultPeekView(
                peek: peek,
                onUndo: { Task { await stateProvider.undoResultPeek() } },
                onRetry: { stateProvider.retryResultPeek() },
                onShowOriginal: {},
                onDismiss: { stateProvider.dismissResultPeek() },
                onHoverChange: { stateProvider.setResultPeekHovered($0) }
            )
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(AppTheme.Recorder.separator)
            .frame(height: 1)
    }

    private func controlBar(_ presentation: RecorderPresentation) -> some View {
        HStack(spacing: 0) {
            Group {
                if presentation.shouldShowCloseButton {
                    RecorderCloseButton(action: onCloseTapped)
                } else {
                    RecorderRecordButton(
                        recordingState: presentation.recordingState,
                        action: onRecordButtonTapped
                    )
                }
            }
            .padding(.leading, 10)

            Spacer(minLength: 0)

            // The visualizer yields while the mode row is open — competing for the same row was
            // squeezing every control down to nothing.
            if !isModeRowExpanded {
                RecorderStatusDisplay(
                    currentState: presentation.recordingState,
                    audioMeterProvider: recorder.audioMeterSnapshot
                )

                Spacer(minLength: 0)
            }

            RecorderModeButton(
                buttonSize: 22,
                padding: EdgeInsets(),
                isExpanded: $isModeRowExpanded
            )
            .padding(.trailing, 12)
        }
        .frame(height: controlBarHeight)
    }
}
