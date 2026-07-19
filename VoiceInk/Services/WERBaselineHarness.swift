import Foundation
import SwiftData

// Runs the held-out golden eval set (ADR-0009) through each candidate model, scores the
// output against the verified ground truth with WordErrorRateCalculator, and persists one
// WEREvaluationResult row per (entry, model). The actual model call is injected via
// WERAudioTranscriber so this orchestration is testable without loading real ML models —
// only the production adapter (TranscriptionServiceRegistryTranscriber, used from the UI)
// touches Whisper/Parakeet for real.
protocol WERAudioTranscriber {
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String
}

enum WERBaselineHarness {

    struct Candidate {
        let entryId: UUID
        let referenceText: String
        let audioURL: URL
    }

    struct ModelSummary {
        let modelDisplayName: String
        let meanWordErrorRate: Double
        let evaluatedCount: Int
        let failedCount: Int
    }

    static func run(
        candidates: [Candidate],
        models: [any TranscriptionModel],
        runLabel: String,
        transcriber: WERAudioTranscriber,
        in modelContext: ModelContext
    ) async -> [ModelSummary] {
        var summaries: [ModelSummary] = []

        for model in models {
            var werValues: [Double] = []
            var failedCount = 0

            for candidate in candidates {
                do {
                    let hypothesis = try await transcriber.transcribe(audioURL: candidate.audioURL, model: model)
                    let result = WordErrorRateCalculator.evaluate(
                        reference: candidate.referenceText, hypothesis: hypothesis)

                    let row = WEREvaluationResult(
                        goldenEvalEntryId: candidate.entryId,
                        modelDisplayName: model.displayName,
                        runLabel: runLabel,
                        hypothesisText: hypothesis,
                        result: result
                    )
                    modelContext.insert(row)
                    werValues.append(result.wordErrorRate)
                } catch {
                    failedCount += 1
                }
            }

            summaries.append(
                ModelSummary(
                    modelDisplayName: model.displayName,
                    meanWordErrorRate: werValues.isEmpty ? 0 : werValues.reduce(0, +) / Double(werValues.count),
                    evaluatedCount: werValues.count,
                    failedCount: failedCount
                ))
        }

        try? modelContext.save()
        return summaries
    }
}

struct TranscriptionServiceRegistryTranscriber: WERAudioTranscriber {
    let registry: TranscriptionServiceRegistry

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        try await registry.transcribe(audioURL: audioURL, model: model)
    }
}
