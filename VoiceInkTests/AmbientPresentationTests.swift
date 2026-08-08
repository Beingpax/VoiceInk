import Testing

@testable import VoiceInk

/// The arbiter that decides what the ambient surface shows. It has been wrong twice, and both times
/// the failure was silent rather than loud: the result peek was gated on a pipeline ID that had
/// always been cleared by the time the peek fired, and the processing crest was gated on a
/// prediction most sessions never have. Nothing crashed either time — things simply never appeared,
/// which is the hardest kind of bug to notice from the outside.
struct AmbientPresentationTests {

    private func resolve(_ inputs: AmbientInputs) -> AmbientPresentation {
        AmbientPresentation.resolve(inputs)
    }

    // MARK: - What colour the light is

    @Test func idleShowsNothing() {
        let result = resolve(AmbientInputs(recordingState: .idle))
        #expect(result.state == .hidden)
        #expect(result.crestPhase == nil)
        #expect(result.captionSlot == .none)
    }

    @Test func healthyRecordingListens() {
        let result = resolve(AmbientInputs(recordingState: .recording, health: .clear))
        #expect(result.state == .listening)
        #expect(result.crestPhase == .live)
    }

    @Test func aFailingInputOutranksRecording() {
        for health in [RecorderInputHealth.silent, .tooLoud] {
            let result = resolve(AmbientInputs(recordingState: .recording, health: health))
            #expect(result.state == .problem)
            // Still live: the crest is how you see the input recovering.
            #expect(result.crestPhase == .live)
        }
    }

    @Test func bothProcessingStatesAreOneColour() {
        // Transcribing and enhancing are the same thing from the outside — the machine is busy.
        for state in [RecordingState.transcribing, .enhancing] {
            #expect(resolve(AmbientInputs(recordingState: state)).state == .working)
        }
    }

    @Test func startingAndBusyStayDark() {
        // These are transitional. Lighting the whole display for them would flash on every take.
        for state in [RecordingState.starting, .busy] {
            #expect(resolve(AmbientInputs(recordingState: state)).state == .hidden)
        }
    }

    // MARK: - The peek outliving the pipeline
    //
    // The original bug: by the time a peek exists, the engine reports idle. Anything that checks
    // the engine first concludes there is nothing to show.

    @Test func aPeekKeepsTheLightOnAfterTheEngineGoesIdle() {
        let result = resolve(
            AmbientInputs(recordingState: .idle, hasResultPeek: true, hasTake: true))
        #expect(result.state == .settled)
        #expect(result.crestPhase == .settled)
        #expect(result.captionSlot == .result)
    }

    @Test func aPeekDoesNotOverrideAnActiveTake() {
        // A stale peek must not repaint a running take as finished.
        let result = resolve(
            AmbientInputs(recordingState: .recording, health: .clear, hasResultPeek: true))
        #expect(result.state == .listening)
    }

    // MARK: - The crest needs something to draw

    @Test func processingWithoutATakeHasNoCrest() {
        // Falls back to the indeterminate lap rather than drawing an empty band.
        let result = resolve(AmbientInputs(recordingState: .transcribing, hasTake: false))
        #expect(result.state == .working)
        #expect(result.crestPhase == nil)
    }

    @Test func processingWithATakeReplaysIt() {
        let result = resolve(AmbientInputs(recordingState: .transcribing, hasTake: true))
        #expect(result.crestPhase == .replay)
    }

    @Test func aSettledPeekWithNoTakeStillShowsTheCaption() {
        let result = resolve(
            AmbientInputs(recordingState: .idle, hasResultPeek: true, hasTake: false))
        #expect(result.state == .settled)
        #expect(result.crestPhase == nil)
        #expect(result.captionSlot == .result)
    }

    // MARK: - Caption priority
    //
    // One slot, so the order is the whole design. Everything here is about what beats what.

    @Test func theResultBeatsEverything() {
        let result = resolve(
            AmbientInputs(
                recordingState: .idle,
                health: .tooLoud,
                hasResultPeek: true,
                silenceCountdown: 3,
                hasLiveTranscript: true
            ))
        #expect(result.captionSlot == .result)
    }

    @Test func processingBeatsAStaleCountdown() {
        let result = resolve(
            AmbientInputs(recordingState: .transcribing, silenceCountdown: 2))
        #expect(result.captionSlot == .processing)
    }

    @Test func theCountdownBeatsTheProblemThatCausedIt() {
        // Silence auto-stop is reported as a problem *and* a countdown. The countdown is strictly
        // more urgent — it is about to end the take.
        let result = resolve(
            AmbientInputs(recordingState: .recording, health: .silent, silenceCountdown: 4))
        #expect(result.captionSlot == .countdown)
    }

    @Test func aProblemBeatsTheTranscript() {
        let result = resolve(
            AmbientInputs(
                recordingState: .recording,
                health: .tooLoud,
                hasLiveTranscript: true,
                hasContextMessage: true
            ))
        #expect(result.captionSlot == .problem)
    }

    @Test func contextIsSaidOnceThenYieldsToTheTranscript() {
        let speaking = AmbientInputs(
            recordingState: .recording,
            health: .clear,
            hasLiveTranscript: true,
            hasContextMessage: true,
            hasShownContext: false
        )
        #expect(resolve(speaking).captionSlot == .context)

        var afterwards = speaking
        afterwards.hasShownContext = true
        #expect(resolve(afterwards).captionSlot == .liveTranscript)
    }

    @Test func theTranscriptTakesTheSlotWhenNothingElseWantsIt() {
        let result = resolve(
            AmbientInputs(recordingState: .recording, health: .clear, hasLiveTranscript: true))
        #expect(result.captionSlot == .liveTranscript)
    }

    @Test func aQuietHealthyTakeSaysNothingAtAll() {
        // The caption is meaningful precisely because it is usually absent.
        let result = resolve(AmbientInputs(recordingState: .recording, health: .clear))
        #expect(result.captionSlot == .none)
    }

    @Test func nothingIsSaidWhileIdleWithoutAPeek() {
        let result = resolve(
            AmbientInputs(recordingState: .idle, health: .tooLoud, hasLiveTranscript: true))
        #expect(result.captionSlot == .none)
    }
}
