import Foundation
import SwiftData

// One row per (golden eval entry, candidate model, run). runLabel groups all rows from a
// single evaluation pass (e.g. "baseline-2026-07-19") so a later post-fine-tune run can be
// compared against the original baseline on the same held-out entries (ADR-0009).
@Model
final class WEREvaluationResult {
    var id: UUID = UUID()
    var goldenEvalEntryId: UUID = UUID()
    var modelDisplayName: String = ""
    var runLabel: String = ""
    var hypothesisText: String = ""
    var wordErrorRate: Double = 0
    var substitutions: Int = 0
    var deletions: Int = 0
    var insertions: Int = 0
    var referenceWordCount: Int = 0
    var timestamp: Date = Date()

    init(
        goldenEvalEntryId: UUID,
        modelDisplayName: String,
        runLabel: String,
        hypothesisText: String,
        result: WordErrorRateCalculator.Result,
        timestamp: Date = Date()
    ) {
        self.id = UUID()
        self.goldenEvalEntryId = goldenEvalEntryId
        self.modelDisplayName = modelDisplayName
        self.runLabel = runLabel
        self.hypothesisText = hypothesisText
        self.wordErrorRate = result.wordErrorRate
        self.substitutions = result.substitutions
        self.deletions = result.deletions
        self.insertions = result.insertions
        self.referenceWordCount = result.referenceWordCount
        self.timestamp = timestamp
    }
}
