import Foundation
import SwiftData

// Builds ADR-0009's golden eval set from recordings VoiceInk already has on disk. One
// GoldenEvalEntry per reviewed Transcription — this service only manages that curation
// step (fetch candidates, save/update/remove a verified entry, report split counts). It does
// not touch WER measurement, which is task #16's concern once this set exists.
enum GoldenEvalSetService {

    struct SplitCounts {
        let train: Int
        let eval: Int
    }

    static func entry(for transcriptionId: UUID, in modelContext: ModelContext) throws -> GoldenEvalEntry? {
        var descriptor = FetchDescriptor<GoldenEvalEntry>(
            predicate: #Predicate<GoldenEvalEntry> { $0.transcriptionId == transcriptionId }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    @discardableResult
    static func save(
        transcriptionId: UUID,
        groundTruthText: String,
        split: GoldenEvalSplit,
        in modelContext: ModelContext
    ) throws -> GoldenEvalEntry {
        if let existing = try entry(for: transcriptionId, in: modelContext) {
            existing.groundTruthText = groundTruthText
            existing.split = split
            existing.verifiedAt = Date()
            try modelContext.save()
            return existing
        }

        let entry = GoldenEvalEntry(transcriptionId: transcriptionId, groundTruthText: groundTruthText, split: split)
        modelContext.insert(entry)
        try modelContext.save()
        return entry
    }

    static func remove(transcriptionId: UUID, in modelContext: ModelContext) throws {
        guard let existing = try entry(for: transcriptionId, in: modelContext) else { return }
        modelContext.delete(existing)
        try modelContext.save()
    }

    static func splitCounts(in modelContext: ModelContext) throws -> SplitCounts {
        let entries = try modelContext.fetch(FetchDescriptor<GoldenEvalEntry>())
        let train = entries.filter { $0.split == .train }.count
        return SplitCounts(train: train, eval: entries.count - train)
    }
}
