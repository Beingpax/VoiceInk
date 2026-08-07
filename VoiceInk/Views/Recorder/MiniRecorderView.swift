import SwiftUI

struct MiniRecorderView<S: RecorderStateProvider & Observable>: View {
    var stateProvider: S
    var recorder: Recorder
    var assistantSession: AssistantSession
    let onRecordButtonTapped: () -> Void
    let onCloseTapped: () -> Void
    let onAssistantFollowUp: (String) -> Void
    @AppStorage(RecorderDisplaySettingsKeys.showLiveTranscript) private var showLiveTranscript = true

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
