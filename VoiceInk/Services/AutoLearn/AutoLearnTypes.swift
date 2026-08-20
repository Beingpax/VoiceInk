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

struct AutoLearnMutationSummary: Sendable {
    let createdCount: Int
    let updatedCount: Int
    let movedCount: Int

    var hasChanges: Bool {
        createdCount > 0 || updatedCount > 0 || movedCount > 0
    }

    static let empty = AutoLearnMutationSummary(createdCount: 0, updatedCount: 0, movedCount: 0)
}

enum AutoLearnLimits {
    static let observationDurationNanoseconds: UInt64 = 20_000_000_000
    static let verificationDelayNanoseconds: UInt64 = 120_000_000
    static let focusChangeGraceNanoseconds: UInt64 = 250_000_000
    static let accessibilityTimeoutSeconds: Float = 0.20
    static let maximumFieldUTF16Length = 100_000
    static let maximumPastedCharacters = 12_000
    static let maximumDiffTokens = 2_048
    static let maximumCandidateCharacters = 256
    static let maximumCandidateTokens = 24
}
