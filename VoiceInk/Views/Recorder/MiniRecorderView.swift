import SwiftUI

struct MiniRecorderView<S: RecorderStateProvider & ObservableObject>: View {
    @ObservedObject var stateProvider: S
    @ObservedObject var recorder: Recorder
    @ObservedObject var assistantSession: AssistantSession
    let onRecordButtonTapped: () -> Void
    let onCloseTapped: () -> Void
    // Cancel ("X"): discard the active recording/transcription with NO paste + resume
    // paused media. Routed up to RecorderUIManager.cancelRecording().
    let onCancelTapped: () -> Void
    let onAssistantFollowUp: (String) -> Void
    @AppStorage(RecorderDisplaySettingsKeys.showLiveTranscript) private var showLiveTranscript = true

    // MARK: - Layout Constants

    private let controlBarHeight: CGFloat = 40
    private let compactWidth: CGFloat = 184
    private let expandedWidth: CGFloat = 300
    private let assistantWidth: CGFloat = 520
    private let compactCornerRadius: CGFloat = 20
    private let expandedCornerRadius: CGFloat = 14

    // true when live transcript is streaming in during recording
    private var hasLiveTranscript: Bool {
        showLiveTranscript
            && stateProvider.recordingState == .recording
            && !stateProvider.partialTranscript.isEmpty
    }

    private var hasAssistantResponse: Bool {
        assistantSession.isVisible
    }

    private var shouldShowCloseButton: Bool {
        hasAssistantResponse &&
            stateProvider.recordingState == .idle &&
            !assistantSession.isBusy
    }

    // The cancel ("X") button is reachable whenever there is something to abort:
    // while RECORDING (discard the audio) AND while a transcription is IN-FLIGHT
    // (.transcribing/.enhancing — abort delivery before it pastes) and during the
    // brief .starting handshake. Hidden at .idle/.busy where there's nothing to
    // cancel (the assistant close-button affordance covers idle dismissal instead).
    private var shouldShowCancelButton: Bool {
        switch stateProvider.recordingState {
        case .starting, .recording, .transcribing, .enhancing:
            return true
        case .idle, .busy:
            return false
        }
    }

    private var liveAssistantFollowUpText: String {
        guard showLiveTranscript, stateProvider.recordingState == .recording else { return "" }
        return stateProvider.partialTranscript
    }

    private var controlBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Group {
                    if shouldShowCloseButton {
                        RecorderCloseButton(action: onCloseTapped)
                    } else {
                        RecorderRecordButton(
                            recordingState: stateProvider.recordingState,
                            action: onRecordButtonTapped
                        )
                    }
                }

                // Cancel ("X") sits immediately to the RIGHT of the Stop/record control
                // so an abort is one glance + one tap away from Stop. Only shown while a
                // recording or in-flight transcription is cancellable (see
                // shouldShowCancelButton); collapses out otherwise so idle bars are unchanged.
                if shouldShowCancelButton {
                    RecorderCancelButton(action: onCancelTapped)
                        .transition(.opacity)
                }
            }
            .padding(.leading, 10)
            .animation(.easeInOut(duration: 0.2), value: shouldShowCancelButton)

            Spacer(minLength: 0)

            RecorderStatusDisplay(
                currentState: stateProvider.recordingState,
                audioMeter: recorder.audioMeter
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

    private var transcriptSection: some View {
        VStack(spacing: 0) {
            if hasLiveTranscript {
                LiveTranscriptView(text: stateProvider.partialTranscript)
                Divider().background(Color.white.opacity(0.15))
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if hasAssistantResponse {
                AssistantPanelView(
                    session: assistantSession,
                    liveFollowUpText: liveAssistantFollowUpText,
                    onSend: onAssistantFollowUp
                )
                Divider().background(Color.white.opacity(0.15))
            } else {
                transcriptSection
            }
            controlBar
        }
        .frame(width: hasAssistantResponse ? assistantWidth : (hasLiveTranscript ? expandedWidth : compactWidth))
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: hasLiveTranscript || hasAssistantResponse ? expandedCornerRadius : compactCornerRadius, style: .continuous))
        .animation(.easeInOut(duration: 0.3), value: hasLiveTranscript)
        .animation(.easeInOut(duration: 0.3), value: hasAssistantResponse)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}
