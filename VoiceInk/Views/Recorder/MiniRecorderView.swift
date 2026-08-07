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

    // MARK: - Layout Constants

    private let controlBarHeight: CGFloat = 40
    private let compactCornerRadius: CGFloat = 20
    private let expandedCornerRadius: CGFloat = 14

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
            isAssistantBusy: assistantSession.isBusy
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
            } else if presentation.hasLiveTranscript {
                LiveTranscriptView(text: presentation.partialTranscript)
                separator
            }

            controlBar(presentation)

            if showsSignalStrip {
                RecorderSignalStrip(
                    health: healthMonitor.health,
                    context: stateProvider.contextSummary,
                    deviceName: AudioDeviceManager.shared.currentInputDeviceName
                )
            }
        }
        .frame(width: width(for: presentation.widthClass))
        .background(
            RecorderChrome(
                cornerRadius: isExpanded ? expandedCornerRadius : compactCornerRadius,
                rimState: presentation.rimState
            )
        )
        .animation(AppTheme.Motion.standard, value: presentation.displayState)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .task(id: presentation.recordingState) {
            guard presentation.recordingState == .recording else {
                healthMonitor.reset()
                return
            }
            // 10Hz sampling, scoped to the take and cancelled with it.
            while !Task.isCancelled {
                healthMonitor.ingest(recorder.audioMeterSnapshot())
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// The strip earns its space only when it has something non-obvious to report.
    private var showsSignalStrip: Bool {
        presentation.recordingState == .recording
            && RecorderSignalStrip.shouldRender(
                health: healthMonitor.health,
                context: stateProvider.contextSummary
            )
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

            RecorderStatusDisplay(
                currentState: presentation.recordingState,
                audioMeterProvider: recorder.audioMeterSnapshot
            )

            Spacer(minLength: 0)

            RecorderModeButton(
                buttonSize: 22,
                padding: EdgeInsets()
            )
            .padding(.trailing, 12)
        }
        .frame(height: controlBarHeight)
    }
}
