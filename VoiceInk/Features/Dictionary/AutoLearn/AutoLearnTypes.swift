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

struct DetectedCorrectionCandidate: Hashable, Sendable {
    let detectedOriginalText: String
    let userCorrectedText: String
    let originalTextContext: String
    let correctedTextContext: String
}

struct AutoLearnReviewCandidate: Sendable {
    let candidateID: UUID
    let detectedOriginalText: String
    let userCorrectedText: String
    let originalTextContext: String
    let correctedTextContext: String
}

enum AutoLearnReviewAction: String, Codable, Sendable {
    case addReplacementAndVocabulary
    case addVocabularyOnly
    case rejectCorrection
}

struct AutoLearnReviewDecision: Sendable {
    let candidateID: UUID
    let learningAction: AutoLearnReviewAction
    let incorrectTextToReplace: String?
    let correctedVocabularyTerm: String?
}

struct AutoLearnReviewResult: Sendable {
    let reviewDecisions: [AutoLearnReviewDecision]
    let unresolvedCandidateIDs: Set<UUID>
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
    let incorrectTextToReplace: String
    let correctedVocabularyTerm: String
    let replacementSourceWasAdded: Bool
    let vocabularyCreationDate: Date?
}

enum AutoLearnReviewSchedule: String, CaseIterable, Identifiable {
    case immediately
    case hourly
    case daily
    case manually

    var id: String { rawValue }

    var title: String {
        switch self {
        case .immediately: String(localized: "Immediately")
        case .hourly: String(localized: "Every hour")
        case .daily: String(localized: "Once daily")
        case .manually: String(localized: "Manually")
        }
    }

    var delay: TimeInterval? {
        switch self {
        case .immediately: 0
        case .hourly: 60 * 60
        case .daily: 24 * 60 * 60
        case .manually: nil
        }
    }
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
    static let maximumReviewBatchCandidates = 25
}
