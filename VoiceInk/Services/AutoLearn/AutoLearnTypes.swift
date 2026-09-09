import Foundation

struct AutoLearnPasteToken: Hashable, Sendable {
    let id: UUID
}

struct AutoLearnRevision: Sendable {
    let original: String
    let corrected: String
    let hasAmbiguousLeadingBoundary: Bool
    let hasAmbiguousTrailingBoundary: Bool

    init(
        original: String,
        corrected: String,
        hasAmbiguousLeadingBoundary: Bool = false,
        hasAmbiguousTrailingBoundary: Bool = false
    ) {
        self.original = original
        self.corrected = corrected
        self.hasAmbiguousLeadingBoundary = hasAmbiguousLeadingBoundary
        self.hasAmbiguousTrailingBoundary = hasAmbiguousTrailingBoundary
    }
}

struct AutoLearnFieldSnapshot: Sendable {
    let baselineFieldText: String
    let finalFieldText: String
    let pastedRange: NSRange
    let originalPastedText: String
}

struct LearnedReplacementCandidate: Hashable, Sendable {
    let source: String
    let destination: String
}

struct AutoLearnReviewCandidate: Codable, Sendable {
    let id: UUID
    let source: String
    let destination: String
}

enum AutoLearnReviewAction: String, Codable, Sendable {
    case replacement
    case vocabulary
    case both
    case reject
}

struct AutoLearnReviewDecision: Codable, Sendable {
    let id: UUID
    let action: AutoLearnReviewAction
}

struct AutoLearnMutationSummary: Sendable {
    let createdCount: Int
    let updatedCount: Int
    let vocabularyCount: Int

    var hasChanges: Bool {
        createdCount > 0 || updatedCount > 0 || vocabularyCount > 0
    }

    static let empty = AutoLearnMutationSummary(createdCount: 0, updatedCount: 0, vocabularyCount: 0)
}

enum AutoLearnLimits {
    static let observationDurationNanoseconds: UInt64 = 20_000_000_000
    static let verificationDelayNanoseconds: UInt64 = 120_000_000
    static let focusChangeGraceNanoseconds: UInt64 = 250_000_000
    static let accessibilityTimeoutSeconds: Float = 0.20
    static let captureAccessibilityTimeoutSeconds: Float = 0.10
    static let captureBudgetNanoseconds: UInt64 = 300_000_000
    static let maximumFieldUTF16Length = 100_000
    static let maximumPastedCharacters = 12_000
    static let maximumDiffTokens = 2_048
    static let maximumCandidateCharacters = 256
    static let maximumCandidateTokens = 24
    static let maximumReviewBatchSize = 24
}
