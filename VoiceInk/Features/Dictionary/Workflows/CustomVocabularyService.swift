import Foundation
import SwiftData

@MainActor
final class CustomVocabularyService {
    static let shared = CustomVocabularyService()

    private init() {}

    func loadSavedVocabulary(from context: ModelContext) -> RecordingVocabulary {
        let descriptor = FetchDescriptor<VocabularyWord>(sortBy: [SortDescriptor(\VocabularyWord.word)])
        let words = (try? context.fetch(descriptor)) ?? []
        return RecordingVocabulary(savedTerms: words.map(\.word))
    }
}
