import Foundation
import Testing

@testable import VoiceInk

struct DictationInsightsTests {

    private let calendar = Calendar(identifier: .gregorian)
    private let today = Date(timeIntervalSince1970: 1_760_000_000)

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: -offset, to: today)!
    }

    private func fact(
        dayOffset: Int = 0,
        words: Int = 100,
        audio: TimeInterval = 60,
        transcription: TimeInterval? = nil,
        enhancement: TimeInterval? = nil,
        mode: String? = nil
    ) -> DictationSessionFact {
        DictationSessionFact(
            day: day(dayOffset),
            words: words,
            audioDuration: audio,
            transcriptionDuration: transcription,
            enhancementDuration: enhancement,
            modeName: mode
        )
    }

    private func make(_ facts: [DictationSessionFact]) -> DictationInsights {
        DictationInsights.make(from: facts, windowDays: 30, today: today, calendar: calendar)
    }

    // MARK: - Refusing to speak too soon

    @Test func tooFewTakesProducesNothing() {
        // A confident number computed from three takes is worse than no number.
        let insights = make(Array(repeating: fact(), count: 4))
        #expect(!insights.hasData)
        #expect(insights.speakingWordsPerMinute == nil)
        #expect(insights.typicalTakeDuration == nil)
    }

    @Test func enoughTakesUnlocksIt() {
        let insights = make(Array(repeating: fact(), count: 5))
        #expect(insights.hasData)
        #expect(insights.speakingWordsPerMinute != nil)
    }

    @Test func silentTakesDoNotProduceAnInfinitePace() {
        let insights = make(Array(repeating: fact(words: 0, audio: 0), count: 6))
        #expect(insights.speakingWordsPerMinute == nil)
        #expect(insights.typicalTakeDuration == nil)
    }

    // MARK: - Pace

    @Test func paceIsWordsOverMinutesSpoken() {
        // 100 words in 60s = 100 wpm.
        let insights = make(Array(repeating: fact(words: 100, audio: 60), count: 6))
        #expect(abs(insights.speakingWordsPerMinute! - 100) < 0.001)
    }

    @Test func paceWeightsLongTakesProperly() {
        // Totals, not an average of per-take rates: one two-word take must not count as much as a
        // five-minute one. 600 words over 360s = 100 wpm, not the 150 a naive mean would give.
        var facts = Array(repeating: fact(words: 100, audio: 60), count: 5)
        facts.append(fact(words: 100, audio: 60))
        facts.append(fact(words: 2, audio: 1))
        let insights = make(facts)
        // 602 words over 361 seconds ≈ 100 wpm. A mean of per-take rates would say ≈ 117.
        let expected = Double(602) / (361.0 / 60)
        #expect(abs(insights.speakingWordsPerMinute! - expected) < 0.001)
    }

    @Test func paceComparesAgainstTyping() {
        let insights = make(Array(repeating: fact(words: 120, audio: 60), count: 6))
        // 120 wpm against a 40 wpm typing yardstick.
        #expect(abs(insights.speedVersusTyping! - 3) < 0.001)
    }

    // MARK: - Typical take

    @Test func typicalTakeIsTheMedianNotTheMean() {
        // One abandoned twenty-minute recording must not redefine "typical".
        var facts = Array(repeating: fact(audio: 30), count: 5)
        facts.append(fact(audio: 1_200))
        let insights = make(facts)
        #expect(insights.typicalTakeDuration == 30)
        #expect(insights.longestTakeDuration == 1_200)
    }

    @Test func medianOfAnEvenCountAveragesTheMiddleTwo() {
        #expect(DictationInsights.median([10, 20, 30, 40]) == 25)
        #expect(DictationInsights.median([10, 20, 30]) == 20)
        #expect(DictationInsights.median([]) == nil)
    }

    // MARK: - The wait

    @Test func theWaitIsTranscriptionPlusEnhancement() {
        let insights = make(
            Array(repeating: fact(transcription: 4, enhancement: 6), count: 6))
        #expect(insights.typicalWaitDuration == 10)
    }

    @Test func theWaitSplitPointsAtTheRightLever() {
        // The actionable half. If enhancement is most of the wait, a faster transcription model
        // will not help — and that is not obvious from a single "processing" number.
        let insights = make(
            Array(repeating: fact(transcription: 2, enhancement: 8), count: 6))
        #expect(abs(insights.enhancementShareOfWait! - 0.8) < 0.001)
    }

    @Test func noEnhancementMeansNoShareRatherThanZeroDivision() {
        let insights = make(Array(repeating: fact(transcription: 3), count: 6))
        #expect(insights.enhancementShareOfWait == 0)
        #expect(insights.typicalWaitDuration == 3)
    }

    @Test func takesWithNoTimingsAreLeftOutOfTheWait() {
        var facts = Array(repeating: fact(transcription: 5), count: 5)
        facts.append(contentsOf: Array(repeating: fact(), count: 5))
        let insights = make(facts)
        #expect(insights.typicalWaitDuration == 5)
    }

    // MARK: - Modes

    @Test func modeShareIsWeightedByWordsNotTakes() {
        // A mode used once for a long dictation is doing more work than one used five times for
        // two-word corrections, and the point of this figure is which mode carries the work.
        var facts = Array(repeating: fact(words: 4, mode: "Quick"), count: 5)
        facts.append(fact(words: 500, mode: "Email"))
        let insights = make(facts)
        #expect(insights.topModeName == "Email")
        #expect(abs(insights.topModeShare! - 500.0 / 520.0) < 0.001)
        #expect(insights.modeCount == 2)
    }

    @Test func takesWithNoModeAreNotCountedAsAMode() {
        var facts = Array(repeating: fact(words: 10, mode: "Email"), count: 5)
        facts.append(fact(words: 10, mode: nil))
        facts.append(fact(words: 10, mode: ""))
        let insights = make(facts)
        #expect(insights.modeCount == 1)
        #expect(insights.topModeShare == 1)
    }

    @Test func noModesAtAllIsNotAnError() {
        let insights = make(Array(repeating: fact(mode: nil), count: 6))
        #expect(insights.topModeName == nil)
        #expect(insights.modeCount == 0)
    }

    // MARK: - Consistency

    @Test func activeDaysCountsDaysNotTakes() {
        let facts = [
            fact(dayOffset: 0), fact(dayOffset: 0), fact(dayOffset: 0),
            fact(dayOffset: 1), fact(dayOffset: 1),
            fact(dayOffset: 5),
        ]
        #expect(make(facts).activeDays == 3)
    }

    @Test func aStreakRunsBackFromToday() {
        let facts = (0..<4).map { fact(dayOffset: $0) } + [fact(dayOffset: 9), fact(dayOffset: 10)]
        #expect(make(facts).currentStreak == 4)
    }

    @Test func yesterdayStillCountsAsAliveStreak() {
        // A streak that breaks at midnight, before you have started work, is a lie.
        let facts = (1..<5).map { fact(dayOffset: $0) } + [fact(dayOffset: 20)]
        #expect(make(facts).currentStreak == 4)
    }

    @Test func anOldRunIsNotACurrentStreak() {
        let facts = (7..<13).map { fact(dayOffset: $0) }
        #expect(make(facts).currentStreak == 0)
    }

    @Test func aGapEndsTheStreak() {
        // Days 0 and 1 are active, 2 is missing, 3 and 4 are active.
        let facts = [
            fact(dayOffset: 0), fact(dayOffset: 1),
            fact(dayOffset: 3), fact(dayOffset: 4), fact(dayOffset: 5), fact(dayOffset: 6),
        ]
        #expect(make(facts).currentStreak == 2)
    }
}
