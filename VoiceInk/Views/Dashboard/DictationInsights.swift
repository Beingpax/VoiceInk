import Foundation

/// What the numbers say about how you actually dictate.
///
/// The dashboard already counted words, minutes and sessions. Those are scoreboard figures — they
/// go up, and knowing they went up changes nothing. These are meant to be the other kind: each one
/// exists because there is a decision behind it.
///
///   * **Pace** turns the time-saved claim from an assertion into arithmetic you can check. It is
///     also the number that tells you whether dictation is actually faster *for you*, rather than
///     faster in general.
///   * **The wait**, split into transcription and enhancement, points at the only two levers that
///     exist. If enhancement is most of it, a faster transcription model will not help you.
///   * **Mode concentration** answers whether the modes you configured are the modes you use. One
///     mode carrying nearly everything means the rest are costing you a decision each take and
///     giving nothing back.
///   * **Consistency** is the only honest read on whether this has become a habit or is still an
///     experiment.
///
/// Deliberately conservative: every figure returns nil rather than guessing when there is too
/// little behind it, because a confident number computed from three takes is worse than no number.
struct DictationInsights: Codable, Equatable, Sendable {
    static let empty = DictationInsights()

    /// Below this the figures are noise, and a dashboard that states noise confidently teaches
    /// people to distrust the rest of it.
    static let minimumSessions = 5

    var sessionCount: Int = 0

    /// Words per minute of speech.
    var speakingWordsPerMinute: Double?
    /// Median take length. Median rather than mean: one abandoned twenty-minute recording should
    /// not redefine what "typical" means.
    var typicalTakeDuration: TimeInterval?
    var longestTakeDuration: TimeInterval?

    /// Median machine time per take — transcription plus enhancement.
    var typicalWaitDuration: TimeInterval?
    /// How much of that wait is enhancement rather than transcription, 0…1.
    var enhancementShareOfWait: Double?

    var topModeName: String?
    /// Share of words produced under `topModeName`, 0…1.
    var topModeShare: Double?
    var modeCount: Int = 0

    /// Days with at least one take, out of the days in the window.
    var activeDays: Int = 0
    var windowDays: Int = 0
    /// Consecutive active days ending today or yesterday. Yesterday still counts, because a streak
    /// that breaks at midnight before you have started work is a lie.
    var currentStreak: Int = 0

    var hasData: Bool { sessionCount >= Self.minimumSessions }

    /// Roughly how fast people type. Used only to phrase pace as a comparison; the underlying
    /// figure is measured, this is the yardstick.
    static let referenceTypingWordsPerMinute: Double = 40

    /// How many times faster than typing, when there is a pace to compare.
    var speedVersusTyping: Double? {
        guard let pace = speakingWordsPerMinute, pace > 0 else { return nil }
        return pace / Self.referenceTypingWordsPerMinute
    }

    static func make(
        from facts: [DictationSessionFact],
        windowDays: Int,
        today: Date,
        calendar: Calendar = .current
    ) -> DictationInsights {
        var insights = DictationInsights()
        insights.sessionCount = facts.count
        insights.windowDays = windowDays
        guard facts.count >= minimumSessions else { return insights }

        // Pace, from totals rather than an average of per-take rates: a two-word take would
        // otherwise carry the same weight as a five-minute one.
        let totalWords = facts.reduce(0) { $0 + $1.words }
        let totalAudio = facts.reduce(0.0) { $0 + $1.audioDuration }
        if totalAudio > 0, totalWords > 0 {
            insights.speakingWordsPerMinute = Double(totalWords) / (totalAudio / 60)
        }

        let durations = facts.map(\.audioDuration).filter { $0 > 0 }
        insights.typicalTakeDuration = median(durations)
        insights.longestTakeDuration = durations.max()

        // The wait, and which half of it is worth attacking.
        let waits = facts.compactMap { fact -> TimeInterval? in
            let transcription = fact.transcriptionDuration ?? 0
            let enhancement = fact.enhancementDuration ?? 0
            let total = transcription + enhancement
            return total > 0 ? total : nil
        }
        insights.typicalWaitDuration = median(waits)

        let transcriptionTotal = facts.compactMap(\.transcriptionDuration).reduce(0, +)
        let enhancementTotal = facts.compactMap(\.enhancementDuration).reduce(0, +)
        if transcriptionTotal + enhancementTotal > 0 {
            insights.enhancementShareOfWait =
                enhancementTotal / (transcriptionTotal + enhancementTotal)
        }

        // Mode concentration, weighted by words rather than takes — a mode used for one long
        // dictation is doing more work than one used for five two-word corrections.
        var wordsByMode: [String: Int] = [:]
        for fact in facts {
            guard let mode = fact.modeName, !mode.isEmpty else { continue }
            wordsByMode[mode, default: 0] += fact.words
        }
        insights.modeCount = wordsByMode.count
        if let top = wordsByMode.max(by: { $0.value < $1.value }) {
            let attributed = wordsByMode.values.reduce(0, +)
            insights.topModeName = top.key
            insights.topModeShare = attributed > 0 ? Double(top.value) / Double(attributed) : nil
        }

        let activeDays = Set(facts.map { calendar.startOfDay(for: $0.day) })
        insights.activeDays = activeDays.count
        insights.currentStreak = streak(endingNear: today, in: activeDays, calendar: calendar)

        return insights
    }

    // MARK: - Helpers

    static func median(_ values: [TimeInterval]) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    /// Counts back from today, or from yesterday if nothing has been dictated yet today.
    static func streak(endingNear today: Date, in activeDays: Set<Date>, calendar: Calendar) -> Int {
        let todayStart = calendar.startOfDay(for: today)
        var cursor: Date
        if activeDays.contains(todayStart) {
            cursor = todayStart
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart),
            activeDays.contains(yesterday)
        {
            cursor = yesterday
        } else {
            return 0
        }

        var length = 0
        while activeDays.contains(cursor) {
            length += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return length
    }
}


/// Everything the insights screen shows, computed together so the views stay dumb.
struct DashboardInsightBundle: Codable, Equatable, Sendable {
    static let empty = DashboardInsightBundle()

    var dictation: DictationInsights = .empty
    var reliability: ReliabilitySummary = .empty
    var enhancement: EnhancementImpactSummary = .empty
    var redictation: RedictationSummary = .empty
    var destinations: DestinationSummary = .empty
    var models: ModelLeaderboard = .empty
    var dictionary: DictionarySummary = .empty
    var library: LibrarySummary = .empty

    static func make(
        sessions: [DictationSessionFact],
        transcripts: [TranscriptFact],
        windowDays: Int,
        today: Date,
        calendar: Calendar = .current
    ) -> DashboardInsightBundle {
        DashboardInsightBundle(
            dictation: .make(
                from: sessions, windowDays: windowDays, today: today, calendar: calendar),
            reliability: .make(from: transcripts),
            enhancement: .make(from: transcripts),
            redictation: .make(from: sessions),
            destinations: .make(from: sessions),
            models: .make(sessions: sessions, transcripts: transcripts),
            dictionary: .make(from: sessions),
            library: .make(from: transcripts)
        )
    }
}
