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

    @Test func entryReturnsNilWhenNoneExists() throws {
        let context = try makeContext()
        #expect(try GoldenEvalSetService.entry(for: UUID(), in: context) == nil)
    }

    @Test func saveCreatesANewEntry() throws {
        let context = try makeContext()
        let transcriptionId = UUID()

        let saved = try GoldenEvalSetService.save(
            transcriptionId: transcriptionId, groundTruthText: "hello world", split: .train, in: context)

        #expect(saved.transcriptionId == transcriptionId)
        #expect(saved.groundTruthText == "hello world")
        #expect(saved.split == .train)
        #expect(try GoldenEvalSetService.entry(for: transcriptionId, in: context)?.groundTruthText == "hello world")
    }

    @Test func savingTwiceForTheSameTranscriptionUpdatesRatherThanDuplicates() throws {
        let context = try makeContext()
        let transcriptionId = UUID()

        try GoldenEvalSetService.save(
            transcriptionId: transcriptionId, groundTruthText: "first draft", split: .eval, in: context)
        try GoldenEvalSetService.save(
            transcriptionId: transcriptionId, groundTruthText: "corrected", split: .train, in: context)

        let entries = try context.fetch(FetchDescriptor<GoldenEvalEntry>())
        #expect(entries.count == 1)
        #expect(entries.first?.groundTruthText == "corrected")
        #expect(entries.first?.split == .train)
    }

    @Test func removeDeletesAnExistingEntry() throws {
        let context = try makeContext()
        let transcriptionId = UUID()
        try GoldenEvalSetService.save(
            transcriptionId: transcriptionId, groundTruthText: "hello", split: .eval, in: context)

        try GoldenEvalSetService.remove(transcriptionId: transcriptionId, in: context)

        #expect(try GoldenEvalSetService.entry(for: transcriptionId, in: context) == nil)
    }

    @Test func removingANonExistentEntryIsANoOp() throws {
        let context = try makeContext()
        // Must not throw.
        try GoldenEvalSetService.remove(transcriptionId: UUID(), in: context)
    }

    @Test func splitCountsTallyTrainAndEvalSeparately() throws {
        let context = try makeContext()
        try GoldenEvalSetService.save(transcriptionId: UUID(), groundTruthText: "a", split: .train, in: context)
        try GoldenEvalSetService.save(transcriptionId: UUID(), groundTruthText: "b", split: .train, in: context)
        try GoldenEvalSetService.save(transcriptionId: UUID(), groundTruthText: "c", split: .eval, in: context)

        let counts = try GoldenEvalSetService.splitCounts(in: context)

        #expect(counts.train == 2)
        #expect(counts.eval == 1)
    }
}
