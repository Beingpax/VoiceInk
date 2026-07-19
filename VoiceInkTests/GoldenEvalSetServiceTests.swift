import Foundation
import SwiftData
import Testing

@testable import VoiceInk

struct GoldenEvalSetServiceTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([GoldenEvalEntry.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    // Fixed, non-random UUIDs (not UUID()) so results are reproducible across every run —
    // no statistical flakiness from runtime-random generation.
    private func fixedId(_ i: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", i))!
    }

    @Test func hasAudioFileIsFalseWhenURLIsNil() {
        let transcription = Transcription(text: "hello", duration: 1.0)
        #expect(GoldenEvalSetService.hasAudioFile(transcription) == false)
    }

    @Test func hasAudioFileIsFalseWhenFileDoesNotExistOnDisk() {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("golden-eval-set-service-tests-\(UUID().uuidString).m4a")
        let transcription = Transcription(
            text: "hello", duration: 1.0, audioFileURL: missingURL.absoluteString)
        #expect(GoldenEvalSetService.hasAudioFile(transcription) == false)
    }

    @Test func hasAudioFileIsTrueWhenFileExistsOnDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("golden-eval-set-service-tests-\(UUID().uuidString).m4a")
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let transcription = Transcription(text: "hello", duration: 1.0, audioFileURL: url.absoluteString)
        #expect(GoldenEvalSetService.hasAudioFile(transcription) == true)
    }

    @Test func entryReturnsNilWhenNoneExists() throws {
        let context = try makeContext()
        #expect(try GoldenEvalSetService.entry(for: UUID(), in: context) == nil)
    }

    @Test func verifyingUneditedTextAssignsControl() throws {
        let context = try makeContext()
        let transcriptionId = UUID()

        let entry = try GoldenEvalSetService.verify(
            transcriptionId: transcriptionId,
            originalText: "hello world",
            groundTruthText: "hello world",
            in: context
        )

        #expect(entry.split == .control)
        #expect(entry.groundTruthText == "hello world")
    }

    @Test func verifyingEditedTextNeverAssignsControl() throws {
        let context = try makeContext()

        for i in 0..<50 {
            let entry = try GoldenEvalSetService.verify(
                transcriptionId: fixedId(i),
                originalText: "hello world",
                groundTruthText: "hello there world",
                in: context
            )
            #expect(entry.split != .control)
        }
    }

    @Test func verifyingTwiceForTheSameTranscriptionUpdatesRatherThanDuplicates() throws {
        let context = try makeContext()
        let transcriptionId = UUID()

        try GoldenEvalSetService.verify(
            transcriptionId: transcriptionId, originalText: "hello", groundTruthText: "hello wrold", in: context)
        try GoldenEvalSetService.verify(
            transcriptionId: transcriptionId, originalText: "hello", groundTruthText: "hello", in: context)

        let entries = try context.fetch(FetchDescriptor<GoldenEvalEntry>())
        #expect(entries.count == 1)
        #expect(entries.first?.groundTruthText == "hello")
        #expect(entries.first?.split == .control)
    }

    @Test func removeDeletesAnExistingEntry() throws {
        let context = try makeContext()
        let transcriptionId = UUID()
        try GoldenEvalSetService.verify(
            transcriptionId: transcriptionId, originalText: "hello", groundTruthText: "hello", in: context)

        try GoldenEvalSetService.remove(transcriptionId: transcriptionId, in: context)

        #expect(try GoldenEvalSetService.entry(for: transcriptionId, in: context) == nil)
    }

    @Test func removingANonExistentEntryIsANoOp() throws {
        let context = try makeContext()
        // Must not throw.
        try GoldenEvalSetService.remove(transcriptionId: UUID(), in: context)
    }

    @Test func assignSplitIsDeterministicForTheSameIdAndSeed() {
        let id = fixedId(42)
        let first = GoldenEvalSetService.assignSplit(originalText: "a", groundTruthText: "b", transcriptionId: id)
        let second = GoldenEvalSetService.assignSplit(originalText: "a", groundTruthText: "b", transcriptionId: id)

        #expect(first == second)
    }

    @Test func splitCountsTallyControlTrainAndEvalSeparately() throws {
        let context = try makeContext()

        // Unedited — always control, regardless of id.
        for i in 0..<10 {
            try GoldenEvalSetService.verify(
                transcriptionId: fixedId(i), originalText: "same", groundTruthText: "same", in: context)
        }
        // Edited — deterministically split between train/eval across a fixed, reproducible
        // set of ids. Loose bounds (not an exact 60/40) since this is a statistical check
        // over a modest sample, not a claim the seed hits the ratio exactly at every n.
        for i in 100..<200 {
            try GoldenEvalSetService.verify(
                transcriptionId: fixedId(i), originalText: "original", groundTruthText: "corrected", in: context)
        }

        let counts = try GoldenEvalSetService.splitCounts(in: context)

        #expect(counts.control == 10)
        #expect(counts.train + counts.eval == 100)
        #expect(counts.train > 40 && counts.train < 80)  // roughly 60%, not degenerately all-one-side
        #expect(counts.eval > 20 && counts.eval < 60)  // roughly 40%
    }
}
