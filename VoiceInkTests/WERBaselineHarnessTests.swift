import Foundation
import SwiftData
import Testing

@testable import VoiceInk

// Real model transcription needs downloaded ML weights VoiceInkTests can't rely on, so this
// harness is designed around an injectable WERAudioTranscriber — the orchestration logic
// (per-candidate error handling, per-model aggregation, persistence) is what's under test
// here, not the models themselves.
private struct FakeTranscriber: WERAudioTranscriber {
    var responses: [String: String] = [:]
    var errorModelNames: Set<String> = []

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        if errorModelNames.contains(model.name) {
            throw NSError(domain: "WERBaselineHarnessTests", code: 1)
        }
        return responses[model.name] ?? ""
    }
}

struct WERBaselineHarnessTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([WEREvaluationResult.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private var sampleModels: [any TranscriptionModel] {
        Array(TranscriptionModelRegistry.models.prefix(2))
    }

    @Test func computesMeanWordErrorRateAcrossCandidatesAndPersistsResults() async throws {
        let context = try makeContext()
        let model = sampleModels[0]
        let candidates = [
            WERBaselineHarness.Candidate(
                entryId: UUID(), referenceText: "hello world", audioURL: URL(fileURLWithPath: "/tmp/a.wav")),
            WERBaselineHarness.Candidate(
                entryId: UUID(), referenceText: "goodbye world", audioURL: URL(fileURLWithPath: "/tmp/b.wav")),
        ]
        // Same canned "hello world" response for both: candidate 1 matches exactly (WER 0),
        // candidate 2 has one substitution out of two reference words (WER 0.5). Mean: 0.25.
        let transcriber = FakeTranscriber(responses: [model.name: "hello world"])

        let summaries = await WERBaselineHarness.run(
            candidates: candidates, models: [model], runLabel: "test-run", transcriber: transcriber, in: context)

        #expect(summaries.count == 1)
        #expect(summaries[0].evaluatedCount == 2)
        #expect(summaries[0].failedCount == 0)
        #expect(abs(summaries[0].meanWordErrorRate - 0.25) < 0.0001)

        let rows = try context.fetch(FetchDescriptor<WEREvaluationResult>())
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.runLabel == "test-run" })
        #expect(rows.allSatisfy { $0.modelDisplayName == model.displayName })
    }

    @Test func failedTranscriptionsAreCountedSeparatelyAndDontCrashTheRun() async throws {
        let context = try makeContext()
        let model = sampleModels[0]
        let candidates = [
            WERBaselineHarness.Candidate(
                entryId: UUID(), referenceText: "hello world", audioURL: URL(fileURLWithPath: "/tmp/a.wav"))
        ]
        let transcriber = FakeTranscriber(errorModelNames: [model.name])

        let summaries = await WERBaselineHarness.run(
            candidates: candidates, models: [model], runLabel: "test-run", transcriber: transcriber, in: context)

        #expect(summaries[0].evaluatedCount == 0)
        #expect(summaries[0].failedCount == 1)
        #expect(summaries[0].meanWordErrorRate == 0)
        #expect(try context.fetch(FetchDescriptor<WEREvaluationResult>()).isEmpty)
    }

    @Test func evaluatesEachCandidateModelIndependently() async throws {
        let context = try makeContext()
        let models = sampleModels
        let candidates = [
            WERBaselineHarness.Candidate(
                entryId: UUID(), referenceText: "hello world", audioURL: URL(fileURLWithPath: "/tmp/a.wav"))
        ]
        let transcriber = FakeTranscriber(responses: [
            models[0].name: "hello world",
            models[1].name: "hola world",
        ])

        let summaries = await WERBaselineHarness.run(
            candidates: candidates, models: models, runLabel: "test-run", transcriber: transcriber, in: context)

        #expect(summaries.count == 2)
        #expect(summaries[0].meanWordErrorRate == 0)
        #expect(abs(summaries[1].meanWordErrorRate - 0.5) < 0.0001)
    }
}
