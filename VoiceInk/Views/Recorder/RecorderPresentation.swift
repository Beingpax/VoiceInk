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
    /// Showing what was just delivered, with undo and retry.
    case result
}

/// What the panel's rim is reporting. One colour, one meaning — the rim is readable peripherally
/// so the state does not have to be decoded from the controls.
enum RecorderRimState: Equatable {
    case neutral
    case recording
    case processing

    init(_ recordingState: RecordingState) {
        switch recordingState {
        case .recording:
            self = .recording
        case .transcribing, .enhancing:
            self = .processing
        case .idle, .starting, .busy:
            self = .neutral
        }
    }

    var color: Color {
        switch self {
        case .neutral: return AppTheme.Recorder.rim
        case .recording: return AppTheme.Recorder.rimRecording
        case .processing: return AppTheme.Recorder.rimProcessing
        }
    }

    /// Outer glow. Absent when neutral so an idle recorder stays quiet.
    var glow: Color? {
        switch self {
        case .neutral: return nil
        case .recording: return AppTheme.Recorder.rimRecording.opacity(0.20)
        case .processing: return AppTheme.Recorder.rimProcessing.opacity(0.18)
        }
    }
}

/// Width grammar: each width means exactly one thing, so a glance at the panel's size already
/// says what it is doing. Previously width changed only for transcript and assistant, and the
/// same width could mean two different things.
enum RecorderWidthClass: Equatable {
    /// Idle or starting — controls only.
    case compact
    /// Recording or processing, nothing to read.
    case standard
    /// Something to read: live transcript, or a result.
    case wide
    /// A conversation.
    case conversation
}

struct RecorderPresentation: Equatable {
    let recordingState: RecordingState
    let displayState: RecorderDisplayState
    let partialTranscript: String
    /// Text to show as a live placeholder in the assistant's follow-up field.
    let assistantFollowUpText: String
    let shouldShowCloseButton: Bool
    let rimState: RecorderRimState
    let widthClass: RecorderWidthClass

    init(
        recordingState: RecordingState,
        partialTranscript: String,
        showLiveTranscript: Bool,
        isAssistantVisible: Bool,
        isAssistantBusy: Bool,
        hasResultPeek: Bool = false
    ) {
        self.recordingState = recordingState
        self.partialTranscript = partialTranscript

        let isRecording = recordingState == .recording
        let hasLiveText = showLiveTranscript && isRecording && !partialTranscript.isEmpty

        if isAssistantVisible {
            displayState = .assistant
        } else if hasResultPeek {
            displayState = .result
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

        rimState = RecorderRimState(recordingState)

        switch displayState {
        case .assistant:
            widthClass = .conversation
        case .liveText, .result:
            widthClass = .wide
        case .active:
            widthClass = .standard
        case .collapsed:
            widthClass = .compact
        }
    }

    var hasLiveTranscript: Bool { displayState == .liveText }
    var isAssistantVisible: Bool { displayState == .assistant }
}
