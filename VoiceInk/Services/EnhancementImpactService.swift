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
