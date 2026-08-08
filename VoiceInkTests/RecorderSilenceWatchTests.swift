import Foundation
import Testing

@testable import VoiceInk

/// The watch exists to stop a take that has been abandoned with the recorder running. The risk it
/// carries is the opposite failure — cutting someone off mid-thought — so most of what is asserted
/// here is that it *doesn't* fire.
@MainActor
struct RecorderSilenceWatchTests {

    private let t0 = Date(timeIntervalSince1970: 1_000)

    @Test func soundDoesNothing() {
        let watch = RecorderSilenceWatch()
        #expect(!watch.ingest(isSilent: false, now: t0))
        #expect(watch.secondsRemaining == nil)
        #expect(!watch.isCountingDown)
    }

    @Test func aShortPauseIsNotACountdown() {
        // Thinking mid-sentence must not start a visible countdown.
        let watch = RecorderSilenceWatch()
        _ = watch.ingest(isSilent: true, now: t0)

        for second in 1...7 {
            let stop = watch.ingest(isSilent: true, now: t0.addingTimeInterval(Double(second)))
            #expect(!stop)
            #expect(watch.secondsRemaining == nil)
        }
    }

    @Test func theCountdownStartsAfterTheGrace() {
        let watch = RecorderSilenceWatch()
        _ = watch.ingest(isSilent: true, now: t0)

        let stop = watch.ingest(isSilent: true, now: t0.addingTimeInterval(8))
        #expect(!stop)
        #expect(watch.secondsRemaining == 5)
        #expect(watch.isCountingDown)
    }

    @Test func theCountdownCountsDown() {
        let watch = RecorderSilenceWatch()
        _ = watch.ingest(isSilent: true, now: t0)

        _ = watch.ingest(isSilent: true, now: t0.addingTimeInterval(9))
        #expect(watch.secondsRemaining == 4)

        _ = watch.ingest(isSilent: true, now: t0.addingTimeInterval(11))
        #expect(watch.secondsRemaining == 2)

        _ = watch.ingest(isSilent: true, now: t0.addingTimeInterval(12.5))
        #expect(watch.secondsRemaining == 1)
    }

    @Test func itStopsTheTakeWhenTheCountdownRunsOut() {
        let watch = RecorderSilenceWatch()
        _ = watch.ingest(isSilent: true, now: t0)
        _ = watch.ingest(isSilent: true, now: t0.addingTimeInterval(8))

        #expect(watch.ingest(isSilent: true, now: t0.addingTimeInterval(13)))
        // And it lets go afterwards, so a stale countdown cannot leak into the next take.
        #expect(watch.secondsRemaining == nil)
    }

    @Test func anySoundCancelsTheCountdown() {
        let watch = RecorderSilenceWatch()
        _ = watch.ingest(isSilent: true, now: t0)
        _ = watch.ingest(isSilent: true, now: t0.addingTimeInterval(11))
        #expect(watch.secondsRemaining == 2)

        #expect(!watch.ingest(isSilent: false, now: t0.addingTimeInterval(11.1)))
        #expect(watch.secondsRemaining == nil)
    }

    @Test func speakingAgainBuysTheFullGraceBack() {
        // No partial credit. After sound, silence starts counting from zero again — otherwise a
        // long take with natural pauses would creep toward a stop it never earned.
        let watch = RecorderSilenceWatch()
        _ = watch.ingest(isSilent: true, now: t0)
        _ = watch.ingest(isSilent: true, now: t0.addingTimeInterval(7))
        _ = watch.ingest(isSilent: false, now: t0.addingTimeInterval(7.5))

        _ = watch.ingest(isSilent: true, now: t0.addingTimeInterval(8))
        _ = watch.ingest(isSilent: true, now: t0.addingTimeInterval(14))
        #expect(watch.secondsRemaining == nil)

        _ = watch.ingest(isSilent: true, now: t0.addingTimeInterval(16))
        #expect(watch.secondsRemaining == 5)
    }

    @Test func resetClearsEverything() {
        let watch = RecorderSilenceWatch()
        _ = watch.ingest(isSilent: true, now: t0)
        _ = watch.ingest(isSilent: true, now: t0.addingTimeInterval(10))
        #expect(watch.isCountingDown)

        watch.reset()
        #expect(watch.secondsRemaining == nil)
        #expect(!watch.isCountingDown)

        // A reset take does not resume from where the last one left off.
        _ = watch.ingest(isSilent: true, now: t0.addingTimeInterval(20))
        #expect(watch.secondsRemaining == nil)
    }

    @Test func aLongUnattendedSilenceStillOnlyStopsOnce() {
        let watch = RecorderSilenceWatch()
        _ = watch.ingest(isSilent: true, now: t0)
        #expect(watch.ingest(isSilent: true, now: t0.addingTimeInterval(60)))
        #expect(!watch.ingest(isSilent: true, now: t0.addingTimeInterval(61)))
    }
}
