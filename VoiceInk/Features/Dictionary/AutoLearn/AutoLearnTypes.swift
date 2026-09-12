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
    let reviewSource: String
    let reviewDestination: String

    init(
        source: String,
        destination: String,
        reviewSource: String? = nil,
        reviewDestination: String? = nil
    ) {
        self.source = source
        self.destination = destination
        self.reviewSource = reviewSource ?? source
        self.reviewDestination = reviewDestination ?? destination
    }
}

struct AutoLearnReviewCandidate: Encodable, Sendable {
    let id: UUID
    let source: String
    let destination: String
    let reviewSource: String
    let reviewDestination: String

    private enum CodingKeys: String, CodingKey {
        case id
        case source
        case destination
        case changedSource
        case changedDestination
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(reviewSource, forKey: .source)
        try container.encode(reviewDestination, forKey: .destination)
        try container.encode(source, forKey: .changedSource)
        try container.encode(destination, forKey: .changedDestination)
    }
}

struct AutoLearnReviewDecision: Codable, Sendable {
    let id: UUID
    let accepted: Bool
    let source: String?
    let destination: String?
}

struct AutoLearnReviewResult: Sendable {
    let decisions: [AutoLearnReviewDecision]
    let unresolvedIDs: Set<UUID>
}

struct AutoLearnMutationSummary: Sendable {
    let createdCount: Int
    let updatedCount: Int
    let vocabularyCount: Int
    let learnedCorrections: [AutoLearnAppliedCorrection]

    var hasChanges: Bool {
        createdCount > 0 || updatedCount > 0 || vocabularyCount > 0
    }

    static let empty = AutoLearnMutationSummary(
        createdCount: 0,
        updatedCount: 0,
        vocabularyCount: 0,
        learnedCorrections: []
    )
}

struct AutoLearnAppliedCorrection: Sendable {
    let source: String
    let destination: String
    let replacementSourceWasAdded: Bool
    let vocabularyCreationDate: Date?
}

enum AutoLearnLimits {
    static let observationDurationNanoseconds: UInt64 = 60_000_000_000
    static let verificationDelayNanoseconds: UInt64 = 120_000_000
    static let focusChangeGraceNanoseconds: UInt64 = 250_000_000
    static let accessibilityTimeoutSeconds: Float = 0.20
    static let captureAccessibilityTimeoutSeconds: Float = 0.10
    static let captureBudgetNanoseconds: UInt64 = 300_000_000
    static let maximumFieldUTF16Length = 100_000
    static let maximumPastedCharacters = 12_000
    static let maximumDiffSegments = 2_048
    static let maximumCandidateCharacters = 256
    static let maximumCandidateSegments = 24
    static let reviewContextSegmentsPerSide = 2
    static let maximumUnspacedCandidateCharacters = 8
    static let maximumPendingCandidates = 100
}
