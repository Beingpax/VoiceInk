import Foundation
import SwiftData

// A hand-verified (audio, ground-truth transcript) pair for ADR-0009's golden eval set.
// One entry per Transcription that's been reviewed — not every Transcription gets one, and
// flagged sessions aren't auto-included (ADR-0009 explicitly warns against folding them in
// for convenience: flag events are an ongoing signal, this is a fixed, deliberate benchmark).
//
// Split is assigned automatically on verification (PRD.md), not picked manually:
// - control: VoiceInk's original transcript needed no correction — a regression check that
//   fine-tuning doesn't degrade cases already handled correctly. Not a percentage; its size is
//   whatever fraction of verified recordings needed zero fixes.
// - train / eval: the transcript needed a correction — randomly split 60/40 with a fixed seed
//   (GoldenEvalSetService.trainEvalSeed) among just this group.
enum GoldenEvalSplit: String, Codable, CaseIterable {
    case control
    case train
    case eval
}

@Model
final class GoldenEvalEntry {
    var id: UUID = UUID()
    var transcriptionId: UUID = UUID()
    var groundTruthText: String = ""
    var splitRawValue: String = GoldenEvalSplit.eval.rawValue
    var verifiedAt: Date = Date()

    var split: GoldenEvalSplit {
        get { GoldenEvalSplit(rawValue: splitRawValue) ?? .eval }
        set { splitRawValue = newValue.rawValue }
    }

    init(
        transcriptionId: UUID,
        groundTruthText: String,
        split: GoldenEvalSplit,
        verifiedAt: Date = Date()
    ) {
        self.id = UUID()
        self.transcriptionId = transcriptionId
        self.groundTruthText = groundTruthText
        self.splitRawValue = split.rawValue
        self.verifiedAt = verifiedAt
    }
}
