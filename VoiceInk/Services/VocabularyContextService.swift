import Foundation
import SwiftUI
import SwiftData

class VocabularyContextService {
    static let shared = VocabularyContextService()

    private init() {}

    private let predefinedWords = "VoiceInk, chatGPT, GPT-4o, GPT-5-mini, Kimi-K2, GLM V4.5, Claude, Claude 4 sonnet, Claude opus, ultrathink, Vibe-coding, groq, cerebras, gpt-oss-120B, deepseek, gemini-2.5, Veo 3, elevenlabs, Kyutai"

    func getVocabularyContext(modelContext: ModelContext) -> String {
        var allWords: [String] = []

        allWords.append(predefinedWords)

        if let customWords = getCustomVocabularyWords(modelContext: modelContext) {
            allWords.append(customWords.joined(separator: ", "))
        }

        let wordsText = allWords.joined(separator: ", ")
        return "Important Vocabulary: \(wordsText)"
    }

    private func getCustomVocabularyWords(modelContext: ModelContext) -> [String]? {
        let descriptor = FetchDescriptor<VocabularyWord>(sortBy: [SortDescriptor(\.word)])

        guard let items = try? modelContext.fetch(descriptor) else {
            return nil
        }

        let words = items.map { $0.word }
        return words.isEmpty ? nil : words
    }
}
