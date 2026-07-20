import Foundation
import SwiftData

// Measures whether AI Enhancement (e.g. Apple Intelligence) is actually helping or hurting
// transcription accuracy — apples to apples, not apples to oranges: both the raw transcript
// and the enhanced text are scored with the same WordErrorRateCalculator against the same
// verified ground truth (GoldenEvalEntry), so a lower WER really means "closer to correct,"
// not an artifact of different measurement rules for each side.
enum EnhancementImpactService {

    struct Entry {
        let transcriptionId: UUID
        let originalText: String
        let enhancedText: String
        let groundTruthText: String
        let werBefore: Double
        let werAfter: Double

        // Positive means enhancement reduced WER (improved accuracy); negative means it made
        // things worse.
        var werDelta: Double { werBefore - werAfter }
    }

    struct Report {
        let entries: [Entry]

        var meanWERBefore: Double {
            entries.isEmpty ? 0 : entries.map(\.werBefore).reduce(0, +) / Double(entries.count)
        }

        var meanWERAfter: Double {
            entries.isEmpty ? 0 : entries.map(\.werAfter).reduce(0, +) / Double(entries.count)
        }

        var improvedCount: Int { entries.filter { $0.werDelta > 0 }.count }
        var regressedCount: Int { entries.filter { $0.werDelta < 0 }.count }
        var unchangedCount: Int { entries.filter { $0.werDelta == 0 }.count }

        // Where enhancement is actively making things worse — the "what needs to be fixed"
        // list, worst first.
        var worstRegressions: [Entry] {
            entries.filter { $0.werDelta < 0 }.sorted { $0.werDelta < $1.werDelta }
        }
    }

    // Verified recordings the report can't score yet: they have ground truth but were dictated
    // before AI enhancement was enabled, so no enhanced text was ever produced. These are the
    // backfill candidates — running their raw transcripts through the current enhancement
    // provider makes them comparable without re-recording anything.
    static func verifiedRecordingsMissingEnhancedText(in modelContext: ModelContext) throws -> [Transcription] {
        let goldenEntries = try modelContext.fetch(FetchDescriptor<GoldenEvalEntry>())

        var missing: [Transcription] = []
        for goldenEntry in goldenEntries {
            let transcriptionId = goldenEntry.transcriptionId
            var descriptor = FetchDescriptor<Transcription>(
                predicate: #Predicate<Transcription> { $0.id == transcriptionId })
            descriptor.fetchLimit = 1

            guard let transcription = try modelContext.fetch(descriptor).first else { continue }
            if transcription.enhancedText?.isEmpty ?? true {
                missing.append(transcription)
            }
        }
        return missing
    }

    struct BackfillOutcome {
        var enhancedCount = 0
        var failedCount = 0
    }

    // The enhance closure is injected so this stays unit-testable and provider-agnostic; the
    // caller passes the same enhancement path live dictations use. Failures skip the recording
    // and keep going — a partial backfill still grows the report.
    @MainActor
    static func backfillEnhancedText(
        for transcriptions: [Transcription],
        in modelContext: ModelContext,
        modelName: String?,
        enhance: (String) async throws -> String,
        progress: ((Int, Int) -> Void)? = nil
    ) async -> BackfillOutcome {
        var outcome = BackfillOutcome()

        for (index, transcription) in transcriptions.enumerated() {
            progress?(index + 1, transcriptions.count)
            do {
                let enhancedText = try await enhance(transcription.text)
                guard !enhancedText.isEmpty else {
                    outcome.failedCount += 1
                    continue
                }
                transcription.enhancedText = enhancedText
                transcription.aiEnhancementModelName = modelName
                outcome.enhancedCount += 1
            } catch {
                outcome.failedCount += 1
            }
        }

        try? modelContext.save()
        return outcome
    }

    // Only verified (Golden Eval Set) recordings qualify — comparing against anything else
    // wouldn't be "ground truth," it'd just be one AI's output scored against another's.
    static func computeReport(in modelContext: ModelContext) throws -> Report {
        let goldenEntries = try modelContext.fetch(FetchDescriptor<GoldenEvalEntry>())

        var entries: [Entry] = []
        for goldenEntry in goldenEntries {
            let transcriptionId = goldenEntry.transcriptionId
            var descriptor = FetchDescriptor<Transcription>(
                predicate: #Predicate<Transcription> { $0.id == transcriptionId })
            descriptor.fetchLimit = 1

            guard let transcription = try modelContext.fetch(descriptor).first,
                let enhancedText = transcription.enhancedText
            else { continue }

            let before = WordErrorRateCalculator.evaluate(
                reference: goldenEntry.groundTruthText, hypothesis: transcription.text)
            let after = WordErrorRateCalculator.evaluate(
                reference: goldenEntry.groundTruthText, hypothesis: enhancedText)

            entries.append(
                Entry(
                    transcriptionId: transcriptionId,
                    originalText: transcription.text,
                    enhancedText: enhancedText,
                    groundTruthText: goldenEntry.groundTruthText,
                    werBefore: before.wordErrorRate,
                    werAfter: after.wordErrorRate
                ))
        }

        return Report(entries: entries)
    }
}
