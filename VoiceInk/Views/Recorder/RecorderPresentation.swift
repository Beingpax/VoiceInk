import SwiftUI

/// The recorder's display state, derived once and shared by both the mini and notch presentations.
///
/// Previously each view re-derived `hasLiveTranscript`, `shouldShowCloseButton` and the assistant
/// follow-up text from the same inputs with the same rules, which let the two surfaces drift.
enum RecorderDisplayState: Equatable {
    /// Nothing to show — the notch collapses to zero height, the mini recorder stays compact.
    case collapsed
    /// Recording or processing, no transcript panel.
    case active
    /// Recording with live transcript streaming in.
    case liveText
    /// Assistant conversation is on screen.
    case assistant
}

struct RecorderPresentation: Equatable {
    let recordingState: RecordingState
    let displayState: RecorderDisplayState
    let partialTranscript: String
    /// Text to show as a live placeholder in the assistant's follow-up field.
    let assistantFollowUpText: String
    let shouldShowCloseButton: Bool

    init(
        recordingState: RecordingState,
        partialTranscript: String,
        showLiveTranscript: Bool,
        isAssistantVisible: Bool,
        isAssistantBusy: Bool
    ) {
        self.recordingState = recordingState
        self.partialTranscript = partialTranscript

        let isRecording = recordingState == .recording
        let hasLiveText = showLiveTranscript && isRecording && !partialTranscript.isEmpty

        if isAssistantVisible {
            displayState = .assistant
        } else {
            switch recordingState {
            case .recording:
                displayState = hasLiveText ? .liveText : .active
            case .transcribing, .enhancing:
                displayState = .active
            case .idle, .starting, .busy:
                displayState = .collapsed
            }
        }

        assistantFollowUpText = (showLiveTranscript && isRecording) ? partialTranscript : ""

        shouldShowCloseButton =
            isAssistantVisible && recordingState == .idle && !isAssistantBusy
    }

    var hasLiveTranscript: Bool { displayState == .liveText }
    var isAssistantVisible: Bool { displayState == .assistant }
}
