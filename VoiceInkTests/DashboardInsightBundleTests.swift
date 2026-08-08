import Foundation
import Testing

@testable import VoiceInk

struct ReliabilitySummaryTests {

    private func transcript(_ status: TranscriptionStatus) -> TranscriptFact {
        TranscriptFact(
            timestamp: Date(timeIntervalSince1970: 1_760_000_000),
            status: status.rawValue,
            rawText: "hello",
            enhancedText: nil,
            promptName: nil,
            modelName: "parakeet",
            audioFileBytes: nil
        )
    }

    @Test func successRateIgnoresCancellations() {
        // Abandoning a take is a decision, not a malfunction. Counting it against the model would
        // make a careful user look like they have unreliable software.
        let summary = ReliabilitySummary.make(
            from: Array(repeating: transcript(.completed), count: 9)
                + [transcript(.failed)]
                + Array(repeating: transcript(.canceled), count: 10)
        )
        #expect(summary.attempted == 10)
        #expect(abs(summary.successRate! - 0.9) < 0.001)
    }

    @Test func cancellationsGetTheirOwnFigure() {
        let summary = ReliabilitySummary.make(
            from: Array(repeating: transcript(.completed), count: 6)
                + Array(repeating: transcript(.canceled), count: 2)
        )
        #expect(abs(summary.cancelRate! - 0.25) < 0.001)
    }

    @Test func pendingTakesAreCountedAsNeither() {
        // A take still in flight is not evidence of anything yet.
        let summary = ReliabilitySummary.make(
            from: Array(repeating: transcript(.completed), count: 5) + [transcript(.pending)])
        #expect(summary.attempted == 5)
    }

    @Test func tooFewAttemptsStaysQuiet() {
        #expect(!ReliabilitySummary.make(from: [transcript(.completed)]).hasData)
    }

    @Test func nothingAtAllDoesNotDivideByZero() {
        let summary = ReliabilitySummary.empty
        #expect(summary.successRate == nil)
        #expect(summary.cancelRate == nil)
    }
}

struct EnhancementImpactTests {

    private func transcript(raw: String, enhanced: String?) -> TranscriptFact {
        TranscriptFact(
            timestamp: Date(timeIntervalSince1970: 1_760_000_000),
            status: TranscriptionStatus.completed.rawValue,
            rawText: raw,
            enhancedText: enhanced,
            promptName: nil,
            modelName: nil,
            audioFileBytes: nil
        )
    }

    @Test func identicalTextMeansNothingChanged() {
        #expect(EnhancementImpactSummary.changeRatio(from: "hello there", to: "hello there") == 0)
    }

    @Test func completelyDifferentTextMeansEverythingChanged() {
        let ratio = EnhancementImpactSummary.changeRatio(from: "aaaaaaaa", to: "bbbbbbbb")
        #expect(ratio == 1)
    }

    @Test func aSmallEditIsASmallRatio() {
        // The case the whole metric exists for: a pass that only tidies punctuation should read as
        // barely doing anything, so you can decide whether it is worth the wait.
        let ratio = EnhancementImpactSummary.changeRatio(
            from: "we should ship it on friday",
            to: "We should ship it on Friday."
        )
        #expect(ratio > 0)
        #expect(ratio < 0.2)
    }

    @Test func aRewriteIsALargeRatio() {
        let ratio = EnhancementImpactSummary.changeRatio(
            from: "um so like i think maybe we could possibly ship it",
            to: "I think we should ship it."
        )
        #expect(ratio > 0.4)
    }

    @Test func emptyInputsDoNotCrash() {
        #expect(EnhancementImpactSummary.changeRatio(from: "", to: "") == 0)
        #expect(EnhancementImpactSummary.changeRatio(from: "abc", to: "") == 1)
        #expect(EnhancementImpactSummary.changeRatio(from: "", to: "abc") == 1)
    }

    @Test func takesWithoutEnhancementAreNotCounted() {
        let summary = EnhancementImpactSummary.make(
            from: Array(repeating: transcript(raw: "hello", enhanced: nil), count: 6))
        #expect(summary.enhancedTakes == 0)
        #expect(summary.medianChangeRatio == nil)
        #expect(summary.enhancementUsageRate == 0)
    }

    @Test func negligibleRewritesAreCountedAsUntouched() {
        // Six identical pairs: enhancement ran and achieved nothing, which is exactly the finding
        // worth surfacing.
        let summary = EnhancementImpactSummary.make(
            from: Array(
                repeating: transcript(raw: "the same sentence", enhanced: "the same sentence"),
                count: 6))
        #expect(summary.enhancedTakes == 6)
        #expect(summary.untouchedTakes == 6)
    }

    @Test func usageRateIsAgainstAllTakes() {
        let facts =
            Array(repeating: transcript(raw: "aaa", enhanced: "bbb"), count: 5)
            + Array(repeating: transcript(raw: "aaa", enhanced: nil), count: 5)
        let summary = EnhancementImpactSummary.make(from: facts)
        #expect(abs(summary.enhancementUsageRate! - 0.5) < 0.001)
    }
}

struct RedictationSummaryTests {

    private let base = Date(timeIntervalSince1970: 1_760_000_000)

    private func fact(at offset: TimeInterval) -> DictationSessionFact {
        DictationSessionFact(
            day: base.addingTimeInterval(offset),
            words: 10,
            audioDuration: 5,
            transcriptionDuration: nil,
            enhancementDuration: nil,
            modeName: nil
        )
    }

    @Test func takesFarApartAreNotRedictations() {
        let summary = RedictationSummary.make(from: (0..<12).map { fact(at: Double($0) * 600) })
        #expect(summary.redictatedTakes == 0)
        #expect(summary.rate == 0)
    }

    @Test func aQuickSecondAttemptCounts() {
        // Nobody records "that was wrong" — they say it again, and the timestamps already know.
        var facts = (0..<10).map { fact(at: Double($0) * 600) }
        facts.append(fact(at: 5))
        let summary = RedictationSummary.make(from: facts)
        #expect(summary.redictatedTakes == 1)
    }

    @Test func theWindowBoundaryIsInclusive() {
        let summary = RedictationSummary.make(from: [fact(at: 0), fact(at: 30)])
        #expect(summary.redictatedTakes == 1)
    }

    @Test func justOutsideTheWindowDoesNotCount() {
        let summary = RedictationSummary.make(from: [fact(at: 0), fact(at: 31)])
        #expect(summary.redictatedTakes == 0)
    }

    @Test func orderDoesNotMatter() {
        // Facts arrive in whatever order the fetch returns them.
        let summary = RedictationSummary.make(from: [fact(at: 20), fact(at: 0), fact(at: 10)])
        #expect(summary.redictatedTakes == 2)
    }

    @Test func aSingleTakeIsNeverARedictation() {
        #expect(RedictationSummary.make(from: [fact(at: 0)]).redictatedTakes == 0)
    }

    @Test func tooFewTakesStaysQuiet() {
        #expect(!RedictationSummary.make(from: (0..<5).map { fact(at: Double($0)) }).hasData)
    }
}

struct DestinationAndDictionaryTests {

    private func fact(
        target: String? = nil, words: Int = 10, hits: Int? = nil, undone: Bool = false,
        model: String? = nil, transcription: TimeInterval? = nil, audio: TimeInterval = 10
    ) -> DictationSessionFact {
        DictationSessionFact(
            day: Date(timeIntervalSince1970: 1_760_000_000),
            words: words,
            audioDuration: audio,
            transcriptionDuration: transcription,
            enhancementDuration: nil,
            modeName: nil,
            transcriptionModelName: model,
            targetBundleIdentifier: target,
            wasUndone: undone,
            dictionaryHitCount: hits
        )
    }

    @Test func destinationsAreRankedByWords() {
        let summary = DestinationSummary.make(from: [
            fact(target: "com.tinyspeck.slackmacgap", words: 100),
            fact(target: "com.apple.dt.Xcode", words: 400),
            fact(target: "com.tinyspeck.slackmacgap", words: 50),
        ])
        #expect(summary.destinations.first?.bundleIdentifier == "com.apple.dt.Xcode")
        #expect(summary.destinations.count == 2)
        #expect(summary.totalWords == 550)
    }

    @Test func takesFromBeforeTrackingAreCountedSeparately() {
        // Not silently folded into a destination — a blank is a gap in the record, not an app.
        let summary = DestinationSummary.make(from: [
            fact(target: nil), fact(target: ""), fact(target: "com.apple.Notes"),
        ])
        #expect(summary.unattributedTakes == 2)
        #expect(summary.destinations.count == 1)
    }

    @Test func unmeasuredDictionaryTakesAreNotTreatedAsZero() {
        // nil means "we weren't recording this yet" and zero means "nothing fired". Folding the
        // first into the second would report a healthy dictionary as useless.
        let summary = DictionarySummary.make(from: [
            fact(hits: nil), fact(hits: nil), fact(hits: 2), fact(hits: 0),
        ])
        #expect(summary.measuredTakes == 2)
        #expect(summary.takesWithHits == 1)
        #expect(summary.totalHits == 2)
        #expect(summary.hitRate == 0.5)
    }

    @Test func aModelIsScoredOnSpeedAndOutcomeTogether() {
        // The fastest model is not the right choice if a chunk of its takes get undone.
        let sessions = [
            fact(undone: true, model: "fast", transcription: 1, audio: 10),
            fact(model: "fast", transcription: 1, audio: 10),
            fact(model: "careful", transcription: 5, audio: 10),
            fact(model: "careful", transcription: 5, audio: 10),
        ]
        let board = ModelLeaderboard.make(sessions: sessions, transcripts: [])
        let fast = board.models.first { $0.name == "fast" }!
        let careful = board.models.first { $0.name == "careful" }!

        #expect(abs(fast.averageSpeedFactor! - 10) < 0.001)
        #expect(abs(careful.averageSpeedFactor! - 2) < 0.001)
        #expect(abs(fast.undoRate! - 0.5) < 0.001)
        #expect(careful.undoRate == 0)
    }

    @Test func modelsWithNoTimingsStillAppear() {
        let board = ModelLeaderboard.make(sessions: [fact(model: "unknown")], transcripts: [])
        #expect(board.models.first?.averageSpeedFactor == nil)
        #expect(board.models.first?.takes == 1)
    }
}
