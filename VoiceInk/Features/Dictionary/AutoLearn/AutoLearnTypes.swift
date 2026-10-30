import Foundation

extension Notification.Name {
    static let autoLearnReviewStateChanged = Notification.Name("AutoLearnReviewStateChanged")
}

enum AutoLearnTextNormalizer {
    /// Produces a comparison-only representation of text exposed by editable
    /// web controls. The original field value remains untouched for anchoring.
    static func accessibilityComparable(_ text: String) -> String {
        let normalizedLineEndings = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\u{200B}", with: "")

        let normalizedBlankLines = normalizedLineEndings
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let value = String(line)
                return value.trimmingCharacters(in: .whitespaces).isEmpty ? "" : value
            }
            .joined(separator: "\n")

        return normalizedBlankLines
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
    }
}

struct AutoLearnPasteToken: Hashable, Sendable {
    let id: UUID
}

struct AutoLearnRevision: Sendable {
    let original: String
    let corrected: String
}

struct AutoLearnFieldSnapshot: Sendable {
    let baselineFieldText: String
    let finalFieldText: String
    let pastedRange: NSRange
    let originalPastedText: String
}

struct DetectedCorrectionCandidate: Hashable, Sendable {
    let originalText: String
    let correctedText: String
}

struct AutoLearnReviewCandidate: Sendable {
    let candidateID: UUID
    let originalText: String
    let correctedText: String
    var observationID: UUID? = nil
}

enum AutoLearnReviewAction: String, Codable, Sendable {
    case addReplacementAndVocabulary
    case addReplacementOnly
    case addVocabularyOnly
    case rejectCorrection
}

struct AutoLearnReviewDecision: Sendable {
    let candidateID: UUID
    let learningAction: AutoLearnReviewAction
    let incorrectTextToReplace: String?
    let correctedVocabularyTerm: String?
    var aiReviewConfigurationID: String? = nil
}

enum AutoLearnSuggestionLimiter {
    static func limit(_ decisions: [AutoLearnReviewDecision], candidates: [AutoLearnReviewCandidate])
        -> [AutoLearnReviewDecision] {
        let observations = Dictionary(candidates.map {
            ($0.candidateID, $0.observationID ?? $0.candidateID)
        }, uniquingKeysWith: { first, _ in first })
        var targetsByObservation: [UUID: Set<String>] = [:]
        return decisions.filter { decision in
            guard let target = decision.correctedVocabularyTerm else { return false }
            let observation = observations[decision.candidateID] ?? decision.candidateID
            let key = WordReplacementVariants.destinationKey(for: target)
            var targets = targetsByObservation[observation, default: []]
            guard targets.contains(key) || targets.count < AutoLearnLimits.maximumSuggestionsPerObservation else { return false }
            targets.insert(key)
            targetsByObservation[observation] = targets
            return true
        }
    }
}

struct AutoLearnSuggestion: Identifiable, Equatable, Sendable {
    struct Original: Identifiable, Equatable, Sendable {
        let id: UUID
        let text: String
        var originalContext: String? = nil
        var correctedContext: String? = nil
        var aiReviewConfigurationID: String? = nil
    }

    let replacementText: String
    let originals: [Original]

    var id: String { replacementText }
    var originalIDs: Set<UUID> { Set(originals.map(\.id)) }

    var isValid: Bool {
        !originals.isEmpty && originals.allSatisfy {
            AutoLearnReviewEligibility.accepts(source: $0.text, destination: replacementText,
                aiReviewConfigurationID: $0.aiReviewConfigurationID)
        }
    }
}

struct AutoLearnReviewProposal: Codable, Identifiable, Sendable {
    let id: UUID
    let candidateID: UUID
    let originalText: String
    let correctedText: String
    let learningAction: AutoLearnReviewAction
    let incorrectTextToReplace: String?
    let correctedVocabularyTerm: String?
}

enum AutoLearnLimits {
    static let observationDurationNanoseconds: UInt64 = 60_000_000_000
    static let verificationDelayNanoseconds: UInt64 = 120_000_000
    static let focusChangeGraceNanoseconds: UInt64 = 250_000_000
    static let accessibilityTimeoutSeconds: Float = 0.20
    static let captureAccessibilityTimeoutSeconds: Float = 0.10
    static let maximumPastedCharacters = 12_000
    static let maximumDiffSegments = 2_048
    static let maximumCandidateCharacters = 64
    static let maximumSuggestionsPerObservation = 3
    static let maximumCandidateSegments = 24
    static let reviewContextSegmentsPerSide = 3
    static let maximumUnspacedCandidateCharacters = 32
}
