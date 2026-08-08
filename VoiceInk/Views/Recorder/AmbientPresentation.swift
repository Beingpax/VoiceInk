import Foundation

/// What the crest is currently drawing. Each is a separate view identity, which is what lets the
/// change between them cross-dissolve: the sample array is swapped wholesale at every boundary and
/// an array cannot be interpolated, so without two crests briefly coexisting the shape snaps.
enum AmbientCrestPhase: Equatable {
    /// Live meter, newest audio under the notch.
    case live
    /// The take being read back while it is transcribed.
    case replay
    /// The finished take, lit and still, while the result is offered.
    case settled
}

/// Which message wins the single caption slot.
///
/// Separated from the payloads so the priority order is a pure function of the take's state and can
/// be tested. It has already been wrong twice — once by gating the result peek on a pipeline ID
/// that was always cleared by the time the peek fired, once by gating the processing crest on a
/// prediction most sessions never have — and both times the failure was invisible rather than loud.
enum AmbientCaptionSlot: Equatable {
    case none
    case result
    case processing
    case countdown
    case problem
    case context
    case liveTranscript
}

/// Everything the ambient surface needs to decide what to show, with no view or engine attached.
struct AmbientInputs: Equatable {
    var recordingState: RecordingState
    var health: RecorderInputHealth
    var hasResultPeek: Bool
    var silenceCountdown: Int?
    /// Whether the user has live text display switched on *and* there is text to show.
    var hasLiveTranscript: Bool
    var hasContextMessage: Bool
    /// The context line is an acknowledgement, not a status field — once said, it stops.
    var hasShownContext: Bool
    /// Whether there is enough of a take recorded to draw a replay.
    var hasTake: Bool

    init(
        recordingState: RecordingState,
        health: RecorderInputHealth = .unknown,
        hasResultPeek: Bool = false,
        silenceCountdown: Int? = nil,
        hasLiveTranscript: Bool = false,
        hasContextMessage: Bool = false,
        hasShownContext: Bool = false,
        hasTake: Bool = false
    ) {
        self.recordingState = recordingState
        self.health = health
        self.hasResultPeek = hasResultPeek
        self.silenceCountdown = silenceCountdown
        self.hasLiveTranscript = hasLiveTranscript
        self.hasContextMessage = hasContextMessage
        self.hasShownContext = hasShownContext
        self.hasTake = hasTake
    }
}

/// The resolved answer: what colour the light is, what the crest draws, what the caption says.
struct AmbientPresentation: Equatable {
    let state: AmbientState
    let crestPhase: AmbientCrestPhase?
    let captionSlot: AmbientCaptionSlot

    static func resolve(_ inputs: AmbientInputs) -> AmbientPresentation {
        let state = resolveState(inputs)
        return AmbientPresentation(
            state: state,
            crestPhase: resolveCrestPhase(state: state, hasTake: inputs.hasTake),
            captionSlot: resolveCaptionSlot(inputs)
        )
    }

    /// One message at a time, chosen by priority rather than combined.
    private static func resolveState(_ inputs: AmbientInputs) -> AmbientState {
        // The peek outlives the pipeline, so it is checked before the engine's own state, which by
        // then reads as idle.
        if inputs.hasResultPeek, inputs.recordingState == .idle { return .settled }

        switch inputs.recordingState {
        case .recording:
            return inputs.health.isProblem ? .problem : .listening
        case .transcribing, .enhancing:
            return .working
        case .idle, .starting, .busy:
            return .hidden
        }
    }

    private static func resolveCrestPhase(state: AmbientState, hasTake: Bool) -> AmbientCrestPhase?
    {
        switch state {
        case .listening, .problem: return .live
        case .working: return hasTake ? .replay : nil
        case .settled: return hasTake ? .settled : nil
        case .hidden: return nil
        }
    }

    /// Priority order, most interruptive first. The live transcript is deliberately last: it runs
    /// for the whole take, so anything that needs saying at a particular moment has to be able to
    /// take the slot from it.
    private static func resolveCaptionSlot(_ inputs: AmbientInputs) -> AmbientCaptionSlot {
        if inputs.hasResultPeek { return .result }

        if inputs.recordingState == .transcribing || inputs.recordingState == .enhancing {
            return .processing
        }

        if inputs.silenceCountdown != nil { return .countdown }

        guard inputs.recordingState == .recording else { return .none }

        if inputs.health.isProblem { return .problem }
        if !inputs.hasShownContext, inputs.hasContextMessage { return .context }
        if inputs.hasLiveTranscript { return .liveTranscript }
        return .none
    }
}
