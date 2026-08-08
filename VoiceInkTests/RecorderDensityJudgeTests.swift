import Foundation
import Testing

@testable import VoiceInk

@MainActor
struct RecorderDensityJudgeTests {

    private func inputs(
        now: Date = Date(timeIntervalSince1970: 1_000),
        recording: Bool = true,
        health: Bool = false,
        contextEmpty: Bool = true,
        realtime: Bool = false,
        liveTranscript: Bool = false,
        unfamiliarMode: Bool = false,
        deviceChanged: Bool = false
    ) -> RecorderDensityJudge.Inputs {
        RecorderDensityJudge.Inputs(
            now: now,
            isRecording: recording,
            hasHealthProblem: health,
            contextIsEmpty: contextEmpty,
            isRealtimeTranscriptionEnabled: realtime,
            showLiveTranscript: liveTranscript,
            isUnfamiliarMode: unfamiliarMode,
            deviceChangedDuringTake: deviceChanged
        )
    }

    @Test func aQuietHealthyTakeStaysMinimal() {
        let judge = RecorderDensityJudge()
        judge.evaluate(inputs())
        #expect(judge.density == .minimal)
    }

    @Test func aProblemEarnsTheStrip() {
        let judge = RecorderDensityJudge()
        judge.evaluate(inputs(health: true))
        #expect(judge.density == .standard)
    }

    @Test func attachedContextEarnsTheStrip() {
        let judge = RecorderDensityJudge()
        judge.evaluate(inputs(contextEmpty: false))
        #expect(judge.density == .standard)
    }

    @Test func anUnfamiliarModeEarnsTheStrip() {
        let judge = RecorderDensityJudge()
        judge.evaluate(inputs(unfamiliarMode: true))
        #expect(judge.density == .standard)
    }

    @Test func aDeviceChangeMidTakeEarnsTheStrip() {
        let judge = RecorderDensityJudge()
        judge.evaluate(inputs(deviceChanged: true))
        #expect(judge.density == .standard)
    }

    @Test func realtimeTranscriptExpands() {
        let judge = RecorderDensityJudge()
        judge.evaluate(inputs(realtime: true, liveTranscript: true))
        #expect(judge.density == .expanded)
    }

    @Test func realtimeEnabledButHiddenDoesNotExpand() {
        let judge = RecorderDensityJudge()
        judge.evaluate(inputs(realtime: true, liveTranscript: false))
        #expect(judge.density == .minimal)
    }

    @Test func aLongTakeExpandsOnItsOwn() {
        let judge = RecorderDensityJudge()
        let start = Date(timeIntervalSince1970: 1_000)

        judge.evaluate(inputs(now: start))
        #expect(judge.density == .minimal)

        judge.evaluate(inputs(now: start.addingTimeInterval(44)))
        #expect(judge.density == .minimal)

        judge.evaluate(inputs(now: start.addingTimeInterval(45)))
        #expect(judge.density == .expanded)
    }

    // MARK: - The ratchet
    //
    // The whole reason this type exists rather than a computed property. A panel that collapses
    // while you are reading it is worse than one that is briefly larger than it needs to be.

    @Test func densityDoesNotShrinkMidTake() {
        let judge = RecorderDensityJudge()

        judge.evaluate(inputs(health: true))
        #expect(judge.density == .standard)

        // Problem clears, but the take is still running.
        judge.evaluate(inputs(health: false))
        #expect(judge.density == .standard)
    }

    @Test func theRatchetOnlyEverClimbs() {
        let judge = RecorderDensityJudge()
        let start = Date(timeIntervalSince1970: 1_000)

        judge.evaluate(inputs(now: start, health: true))
        #expect(judge.density == .standard)

        judge.evaluate(inputs(now: start.addingTimeInterval(45)))
        #expect(judge.density == .expanded)

        judge.evaluate(inputs(now: start.addingTimeInterval(46)))
        #expect(judge.density == .expanded)
    }

    @Test func endingTheTakeReleasesTheRatchet() {
        let judge = RecorderDensityJudge()

        judge.evaluate(inputs(health: true))
        judge.endTake()
        #expect(judge.density == .minimal)

        // And a fresh take starts from the floor again rather than inheriting the last one.
        judge.evaluate(inputs())
        #expect(judge.density == .minimal)
    }

    @Test func aLongTakeDoesNotCarryItsClockIntoTheNextOne() {
        // takeStartedAt has to be cleared, or the next take reads as instantly 45s old.
        let judge = RecorderDensityJudge()
        let start = Date(timeIntervalSince1970: 1_000)

        judge.evaluate(inputs(now: start))
        judge.evaluate(inputs(now: start.addingTimeInterval(60)))
        #expect(judge.density == .expanded)

        judge.evaluate(inputs(now: start.addingTimeInterval(61), recording: false))
        judge.endTake()

        judge.evaluate(inputs(now: start.addingTimeInterval(62)))
        #expect(judge.density == .minimal)
    }

    @Test func whenIdleTheRatchetIsIgnored() {
        // Between takes the panel reflects current conditions, not the high-water mark of the
        // take that just finished.
        let judge = RecorderDensityJudge()

        judge.evaluate(inputs(health: true))
        #expect(judge.density == .standard)

        judge.evaluate(inputs(recording: false))
        #expect(judge.density == .minimal)
    }
}

@MainActor
struct RecorderModeFamiliarityTests {

    @Test func anUnusedModeIsUnfamiliar() {
        let mode = UUID()
        defer { UserDefaults.standard.removeObject(forKey: "recorderModeUseCount." + mode.uuidString) }

        #expect(RecorderModeFamiliarity.isUnfamiliar(mode))
    }

    @Test func aModeBecomesFamiliarAfterTheThirdUse() {
        let mode = UUID()
        defer { UserDefaults.standard.removeObject(forKey: "recorderModeUseCount." + mode.uuidString) }

        for _ in 0..<(RecorderDensityJudge.newModeUseThreshold - 1) {
            RecorderModeFamiliarity.recordUse(of: mode)
        }
        #expect(RecorderModeFamiliarity.isUnfamiliar(mode))

        RecorderModeFamiliarity.recordUse(of: mode)
        #expect(!RecorderModeFamiliarity.isUnfamiliar(mode))
    }

    @Test func noModeIsNotUnfamiliar() {
        // Nil means "no mode selected", which must not be treated as a brand new mode and
        // permanently force the fuller panel.
        #expect(!RecorderModeFamiliarity.isUnfamiliar(nil))
    }

    @Test func countsAreKeptPerMode() {
        let a = UUID()
        let b = UUID()
        defer {
            UserDefaults.standard.removeObject(forKey: "recorderModeUseCount." + a.uuidString)
            UserDefaults.standard.removeObject(forKey: "recorderModeUseCount." + b.uuidString)
        }

        for _ in 0..<5 { RecorderModeFamiliarity.recordUse(of: a) }

        #expect(!RecorderModeFamiliarity.isUnfamiliar(a))
        #expect(RecorderModeFamiliarity.isUnfamiliar(b))
    }
}
