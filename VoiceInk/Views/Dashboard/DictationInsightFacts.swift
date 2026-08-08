import Foundation

/// A take, reduced to the fields the insights need, so the arithmetic can be tested without a
/// database behind it.
struct DictationSessionFact: Sendable, Equatable {
    let day: Date
    let words: Int
    let audioDuration: TimeInterval
    let transcriptionDuration: TimeInterval?
    let enhancementDuration: TimeInterval?
    let modeName: String?
    var transcriptionModelName: String?
    var targetBundleIdentifier: String?
    var wasUndone: Bool = false
    var dictionaryHitCount: Int?
}

/// A transcript, reduced the same way. Separate from `DictationSessionFact` because these come from
/// a different table and, crucially, a different population: `SessionMetric` only exists for takes
/// that completed, so anything about failure or cancellation has to be read from here.
struct TranscriptFact: Sendable, Equatable {
    let timestamp: Date
    let status: String?
    let rawText: String
    let enhancedText: String?
    let promptName: String?
    let modelName: String?
    let audioFileBytes: Int64?
}

// MARK: - Reliability

/// What share of takes actually produced something usable.
///
/// Read from transcripts rather than session metrics: a metric is only written when a take
/// completes, so measuring failure from that table would always report a perfect record.
struct ReliabilitySummary: Codable, Equatable, Sendable {
    static let empty = ReliabilitySummary()

    var completed: Int = 0
    var failed: Int = 0
    var canceled: Int = 0

    /// Cancellations are excluded from the denominator on purpose. Abandoning a take is a decision,
    /// not a malfunction, and counting it as one would make a careful user look unreliable.
    var attempted: Int { completed + failed }
    var hasData: Bool { attempted >= 5 }

    var successRate: Double? {
        guard attempted > 0 else { return nil }
        return Double(completed) / Double(attempted)
    }

    /// Cancellations as a share of everything started — a separate question, worth its own figure.
    var cancelRate: Double? {
        let total = completed + failed + canceled
        guard total > 0 else { return nil }
        return Double(canceled) / Double(total)
    }

    static func make(from transcripts: [TranscriptFact]) -> ReliabilitySummary {
        var summary = ReliabilitySummary()
        for transcript in transcripts {
            switch transcript.status {
            case TranscriptionStatus.completed.rawValue: summary.completed += 1
            case TranscriptionStatus.failed.rawValue: summary.failed += 1
            case TranscriptionStatus.canceled.rawValue: summary.canceled += 1
            default: break
            }
        }
        return summary
    }
}

// MARK: - Enhancement impact

/// How much the AI pass actually changes what you said.
///
/// The question this answers is whether enhancement is earning the wait and the money. A model that
/// rewrites a third of your words is doing real work; one that changes two commas is not, and
/// nothing in the app was in a position to tell you which you had.
struct EnhancementImpactSummary: Codable, Equatable, Sendable {
    static let empty = EnhancementImpactSummary()

    var enhancedTakes: Int = 0
    var totalTakes: Int = 0
    /// Median share of characters changed, 0…1.
    var medianChangeRatio: Double?
    /// Takes where enhancement changed essentially nothing.
    var untouchedTakes: Int = 0

    var hasData: Bool { enhancedTakes >= 5 }

    var enhancementUsageRate: Double? {
        guard totalTakes > 0 else { return nil }
        return Double(enhancedTakes) / Double(totalTakes)
    }

    /// Below this the pass has effectively rewritten nothing.
    static let negligibleChange = 0.02

    static func make(from transcripts: [TranscriptFact]) -> EnhancementImpactSummary {
        var summary = EnhancementImpactSummary()
        summary.totalTakes = transcripts.count

        var ratios: [Double] = []
        for transcript in transcripts {
            guard let enhanced = transcript.enhancedText, !enhanced.isEmpty,
                !transcript.rawText.isEmpty
            else { continue }
            summary.enhancedTakes += 1
            let ratio = changeRatio(from: transcript.rawText, to: enhanced)
            ratios.append(ratio)
            if ratio < negligibleChange { summary.untouchedTakes += 1 }
        }

        summary.medianChangeRatio = DictationInsights.median(ratios)
        return summary
    }

    /// Proportion of characters that differ, using the longest common subsequence.
    ///
    /// Full edit distance on two long transcripts is quadratic in both time *and* memory, and this
    /// runs over every take in the window. LCS gives the same answer for the question being asked —
    /// how much survived the rewrite — and needs only two rows of the table at a time.
    static func changeRatio(from original: String, to enhanced: String) -> Double {
        let a = Array(original.unicodeScalars)
        let b = Array(enhanced.unicodeScalars)
        guard !a.isEmpty || !b.isEmpty else { return 0 }
        guard !a.isEmpty, !b.isEmpty else { return 1 }

        // Long transcripts are compared on a prefix. The ratio is stable well before this, and the
        // cost of being exact on a 10,000-character dictation is not worth paying on every load.
        let limit = 2_000
        let left = Array(a.prefix(limit))
        let right = Array(b.prefix(limit))

        var previous = [Int](repeating: 0, count: right.count + 1)
        var current = previous
        for i in 1...left.count {
            for j in 1...right.count {
                current[j] =
                    left[i - 1] == right[j - 1]
                    ? previous[j - 1] + 1
                    : max(previous[j], current[j - 1])
            }
            swap(&previous, &current)
        }

        let common = previous[right.count]
        let longest = max(left.count, right.count)
        guard longest > 0 else { return 0 }
        return 1 - (Double(common) / Double(longest))
    }
}

// MARK: - Re-dictation

/// How often a take is immediately followed by another.
///
/// The closest thing to an accuracy measure available without asking the user anything. Nobody
/// records "that was wrong" — they just say it again, and the timestamps already know.
struct RedictationSummary: Codable, Equatable, Sendable {
    static let empty = RedictationSummary()

    var totalTakes: Int = 0
    var redictatedTakes: Int = 0

    var hasData: Bool { totalTakes >= 10 }

    var rate: Double? {
        guard totalTakes > 0 else { return nil }
        return Double(redictatedTakes) / Double(totalTakes)
    }

    /// A gap this short is someone correcting themselves rather than starting new work. Long enough
    /// to cover reading the result and reacting; short enough that a genuine second thought does
    /// not get counted.
    static let window: TimeInterval = 30

    static func make(from facts: [DictationSessionFact]) -> RedictationSummary {
        var summary = RedictationSummary()
        summary.totalTakes = facts.count
        guard facts.count > 1 else { return summary }

        let times = facts.map(\.day).sorted()
        for index in 0..<(times.count - 1) where times[index + 1].timeIntervalSince(times[index]) <= window {
            summary.redictatedTakes += 1
        }
        return summary
    }
}

// MARK: - Where the words go

struct DestinationShare: Codable, Equatable, Sendable, Identifiable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    let takes: Int
    let words: Int
}

struct DestinationSummary: Codable, Equatable, Sendable {
    static let empty = DestinationSummary()

    var destinations: [DestinationShare] = []
    /// Takes with no destination recorded — everything from before this was tracked.
    var unattributedTakes: Int = 0

    var hasData: Bool { !destinations.isEmpty }

    var totalWords: Int { destinations.reduce(0) { $0 + $1.words } }

    static func make(from facts: [DictationSessionFact]) -> DestinationSummary {
        var byApp: [String: (takes: Int, words: Int)] = [:]
        var unattributed = 0

        for fact in facts {
            guard let bundle = fact.targetBundleIdentifier, !bundle.isEmpty else {
                unattributed += 1
                continue
            }
            byApp[bundle, default: (0, 0)].takes += 1
            byApp[bundle, default: (0, 0)].words += fact.words
        }

        var summary = DestinationSummary()
        summary.unattributedTakes = unattributed
        summary.destinations =
            byApp
            .map { DestinationShare(bundleIdentifier: $0.key, takes: $0.value.takes, words: $0.value.words) }
            .sorted { $0.words > $1.words }
        return summary
    }
}

// MARK: - Model leaderboard

struct ModelScorecard: Codable, Equatable, Sendable, Identifiable {
    var id: String { name }
    let name: String
    let takes: Int
    /// Multiple of realtime. Higher is faster.
    let averageSpeedFactor: Double?
    let successRate: Double?
    let undoRate: Double?
}

/// Speed and reliability side by side, because either one alone is misleading — the fastest model
/// is not a good choice if a twentieth of its takes have to be redone.
struct ModelLeaderboard: Codable, Equatable, Sendable {
    static let empty = ModelLeaderboard()

    var models: [ModelScorecard] = []
    var hasData: Bool { models.count >= 1 }

    static func make(
        sessions: [DictationSessionFact],
        transcripts: [TranscriptFact]
    ) -> ModelLeaderboard {
        var speed: [String: (total: Double, count: Int)] = [:]
        var undone: [String: (undone: Int, count: Int)] = [:]

        for fact in sessions {
            guard let name = fact.transcriptionModelName, !name.isEmpty else { continue }
            if let duration = fact.transcriptionDuration, duration > 0, fact.audioDuration > 0 {
                speed[name, default: (0, 0)].total += fact.audioDuration / duration
                speed[name, default: (0, 0)].count += 1
            }
            undone[name, default: (0, 0)].count += 1
            if fact.wasUndone { undone[name, default: (0, 0)].undone += 1 }
        }

        var outcome: [String: (completed: Int, attempted: Int)] = [:]
        for transcript in transcripts {
            guard let name = transcript.modelName, !name.isEmpty else { continue }
            switch transcript.status {
            case TranscriptionStatus.completed.rawValue:
                outcome[name, default: (0, 0)].completed += 1
                outcome[name, default: (0, 0)].attempted += 1
            case TranscriptionStatus.failed.rawValue:
                outcome[name, default: (0, 0)].attempted += 1
            default: break
            }
        }

        let names = Set(speed.keys).union(undone.keys).union(outcome.keys)
        var board = ModelLeaderboard()
        board.models =
            names
            .map { name -> ModelScorecard in
                let speedEntry = speed[name]
                let undoEntry = undone[name]
                let outcomeEntry = outcome[name]
                return ModelScorecard(
                    name: name,
                    takes: undoEntry?.count ?? outcomeEntry?.attempted ?? 0,
                    averageSpeedFactor: speedEntry.map { $0.total / Double($0.count) },
                    successRate: outcomeEntry.flatMap {
                        $0.attempted > 0 ? Double($0.completed) / Double($0.attempted) : nil
                    },
                    undoRate: undoEntry.flatMap {
                        $0.count > 0 ? Double($0.undone) / Double($0.count) : nil
                    }
                )
            }
            .sorted { $0.takes > $1.takes }
        return board
    }
}

// MARK: - Dictionary

struct DictionarySummary: Codable, Equatable, Sendable {
    static let empty = DictionarySummary()

    /// Takes where we actually measured — nil counts are older takes and must not be read as zero.
    var measuredTakes: Int = 0
    var takesWithHits: Int = 0
    var totalHits: Int = 0

    var hasData: Bool { measuredTakes >= 10 }

    var hitRate: Double? {
        guard measuredTakes > 0 else { return nil }
        return Double(takesWithHits) / Double(measuredTakes)
    }

    static func make(from facts: [DictationSessionFact]) -> DictionarySummary {
        var summary = DictionarySummary()
        for fact in facts {
            guard let hits = fact.dictionaryHitCount else { continue }
            summary.measuredTakes += 1
            summary.totalHits += hits
            if hits > 0 { summary.takesWithHits += 1 }
        }
        return summary
    }
}

// MARK: - Prompts and storage

struct PromptShare: Codable, Equatable, Sendable, Identifiable {
    var id: String { name }
    let name: String
    let takes: Int
}

struct LibrarySummary: Codable, Equatable, Sendable {
    static let empty = LibrarySummary()

    var prompts: [PromptShare] = []
    var retainedAudioBytes: Int64 = 0
    var retainedAudioFiles: Int = 0
    var oldestRetainedAudio: Date?

    var hasData: Bool { !prompts.isEmpty || retainedAudioFiles > 0 }

    static func make(from transcripts: [TranscriptFact]) -> LibrarySummary {
        var summary = LibrarySummary()
        var byPrompt: [String: Int] = [:]

        for transcript in transcripts {
            if let prompt = transcript.promptName, !prompt.isEmpty {
                byPrompt[prompt, default: 0] += 1
            }
            if let bytes = transcript.audioFileBytes, bytes > 0 {
                summary.retainedAudioBytes += bytes
                summary.retainedAudioFiles += 1
                if let oldest = summary.oldestRetainedAudio {
                    summary.oldestRetainedAudio = min(oldest, transcript.timestamp)
                } else {
                    summary.oldestRetainedAudio = transcript.timestamp
                }
            }
        }

        summary.prompts =
            byPrompt.map { PromptShare(name: $0.key, takes: $0.value) }
            .sorted { $0.takes > $1.takes }
        return summary
    }
}
