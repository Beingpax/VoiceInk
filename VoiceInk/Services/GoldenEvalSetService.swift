import Foundation
import SwiftData

// Builds ADR-0009's golden eval set from recordings VoiceInk already has on disk. One
// GoldenEvalEntry per reviewed Transcription — this service only manages that curation
// step (fetch candidates, verify an entry, report split counts). It does not touch WER
// measurement, which is task #16's concern once this set exists.
enum GoldenEvalSetService {

    struct SplitCounts {
        let control: Int
        let train: Int
        let eval: Int
    }

    // Fixed constant, not generated-and-persisted (PRD.md) — deterministic and "recorded"
    // simply by being in git history. Only used to place entries that needed a correction
    // into train vs eval; entries needing no correction always go to control regardless of
    // this seed (see assignSplit).
    static let trainEvalSeed: UInt64 = 20_260_719

    static func hasAudioFile(_ transcription: Transcription) -> Bool {
        guard let urlString = transcription.audioFileURL, let url = URL(string: urlString) else {
            return false
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func entry(for transcriptionId: UUID, in modelContext: ModelContext) throws -> GoldenEvalEntry? {
        var descriptor = FetchDescriptor<GoldenEvalEntry>(
            predicate: #Predicate<GoldenEvalEntry> { $0.transcriptionId == transcriptionId }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    // Automatic categorization, replacing manual train/eval picking (PRD.md): unedited
    // transcripts are a regression check (control), edited ones are randomly split 60/40
    // train/eval using a fixed seed so the same recording always lands the same way.
    static func assignSplit(originalText: String, groundTruthText: String, transcriptionId: UUID) -> GoldenEvalSplit {
        guard groundTruthText != originalText else {
            return .control
        }
        return deterministicFraction(for: transcriptionId, seed: trainEvalSeed) < 0.6 ? .train : .eval
    }

    @discardableResult
    static func verify(
        transcriptionId: UUID,
        originalText: String,
        groundTruthText: String,
        in modelContext: ModelContext
    ) throws -> GoldenEvalEntry {
        let split = assignSplit(originalText: originalText, groundTruthText: groundTruthText, transcriptionId: transcriptionId)

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
        let control = entries.filter { $0.split == .control }.count
        let train = entries.filter { $0.split == .train }.count
        return SplitCounts(control: control, train: train, eval: entries.count - control - train)
    }

    // Deterministic pseudo-random value in [0, 1) derived from an id + seed. Deliberately not
    // UUID.hashValue / Swift's Hasher — those are randomized per process launch (by design,
    // for hash-flooding resistance), which would make the same recording land in a different
    // split on every app run. FNV-1a over the UUID's raw bytes, salted with the seed, is
    // stable across runs and processes.
    private static func deterministicFraction(for id: UUID, seed: UInt64) -> Double {
        var hash: UInt64 = 14_695_981_039_346_656_037 ^ seed
        withUnsafeBytes(of: id.uuid) { buffer in
            for byte in buffer {
                hash ^= UInt64(byte)
                hash = hash &* 1_099_511_628_211
            }
        }
        return Double(hash % 1_000_000) / 1_000_000.0
    }
}
