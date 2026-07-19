import SwiftData

// Single source of truth for VoiceInk's SwiftData model container setup, shared between
// VoiceInkApp's real container builders and AppModelSchemaTests' regression coverage.
//
// VoiceInk splits storage across three named ModelConfigurations (default/dictionary/stats
// stores), each declaring its own schema subset, combined under one top-level `combined`
// schema passed to ModelContainer(for:configurations:). SwiftData routes each @Model type's
// storage by matching it against a *configuration's* declared schema, not the combined one —
// a type present only in `combined` has no store to write to, and crashes at save time
// (not at container creation) instead of throwing cleanly. Keep new models: only-in-`combined`
// and never in one of transcript/dictionary/stats.
enum AppModelSchema {
    static let combined = Schema([
        Transcription.self,
        VocabularyWord.self,
        WordReplacement.self,
        SessionMetric.self,
        GoldenEvalEntry.self,
        WEREvaluationResult.self,
    ])

    static let transcript = Schema([Transcription.self, GoldenEvalEntry.self, WEREvaluationResult.self])
    static let dictionary = Schema([VocabularyWord.self, WordReplacement.self])
    static let stats = Schema([SessionMetric.self])
}
