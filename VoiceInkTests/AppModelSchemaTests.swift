import SwiftData
import Testing

@testable import VoiceInk

// Regression coverage for a real crash: clicking "Mark Verified" fatally crashed the running
// app (EXC_BREAKPOINT in ModelContext.save(), GoldenEvalSetService.swift) because
// GoldenEvalEntry/WEREvaluationResult were declared only in the combined top-level Schema
// passed to ModelContainer(for:), not in any individual ModelConfiguration's own schema.
// VoiceInk splits storage across three named configurations (default/dictionary/stats
// stores) — SwiftData routes a @Model type's storage by matching it against a
// *configuration's* declared schema, not the combined one, so a type missing from every
// per-store schema has nowhere to write to and crashes at save time. Regular unit tests using
// a single-schema in-memory container (see GoldenEvalSetServiceTests) never exercise this
// multi-configuration setup, so this bug shipped silently until someone used the real app.
struct AppModelSchemaTests {

    // The structural invariant that broke: every model declared in the combined schema must
    // also be declared in at least one of the individual store schemas.
    @Test func everyCombinedSchemaModelIsDeclaredInAStoreSchema() {
        let combinedNames = Set(AppModelSchema.combined.entities.map(\.name))
        let configuredNames = Set(
            AppModelSchema.transcript.entities.map(\.name)
                + AppModelSchema.dictionary.entities.map(\.name)
                + AppModelSchema.stats.entities.map(\.name)
        )

        #expect(combinedNames == configuredNames)
    }

    // Literal reproduction: build a container with the exact same multi-configuration shape
    // VoiceInkApp uses in production, and confirm every model type can actually be inserted
    // and saved — not just that the container initializes without throwing.
    @Test func everyModelCanBeInsertedAndSavedInTheRealMultiStoreContainer() throws {
        let container = try ModelContainer(
            for: AppModelSchema.combined,
            configurations:
                ModelConfiguration("default-test", schema: AppModelSchema.transcript, isStoredInMemoryOnly: true),
                ModelConfiguration(
                    "dictionary-test", schema: AppModelSchema.dictionary, isStoredInMemoryOnly: true),
                ModelConfiguration("stats-test", schema: AppModelSchema.stats, isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let transcription = Transcription(text: "hello world", duration: 2.0)
        context.insert(transcription)
        try context.save()

        let goldenEvalEntry = GoldenEvalEntry(
            transcriptionId: transcription.id, groundTruthText: "hello world", split: .control)
        context.insert(goldenEvalEntry)
        try context.save()

        let werResult = WEREvaluationResult(
            goldenEvalEntryId: goldenEvalEntry.id,
            modelDisplayName: "Test Model",
            runLabel: "test-run",
            hypothesisText: "hello world",
            result: WordErrorRateCalculator.Result(
                substitutions: 0, deletions: 0, insertions: 0, referenceWordCount: 2)
        )
        context.insert(werResult)
        try context.save()

        context.insert(VocabularyWord(word: "VoiceInk"))
        try context.save()

        context.insert(WordReplacement(originalText: "voice ink", replacementText: "VoiceInk"))
        try context.save()

        context.insert(
            SessionMetric(
                transcriptionId: transcription.id,
                wordCount: 2,
                audioDuration: 2.0,
                transcriptionModelName: "Parakeet V3",
                transcriptionDuration: 0.5,
                speedFactor: 4.0,
                modeName: nil,
                aiEnhancementModelName: nil,
                enhancementDuration: nil
            ))
        try context.save()
    }
}
