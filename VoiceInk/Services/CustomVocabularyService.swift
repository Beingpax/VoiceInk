import Foundation
import SwiftUI

class CustomVocabularyService {
    static let shared = CustomVocabularyService()

    private init() {
        // Migrate old key to new key if needed
        migrateOldDataIfNeeded()
    }

    func getCustomVocabulary() -> String {
        guard let customWords = getCustomVocabularyWords(), !customWords.isEmpty else {
            return ""
        }

        let wordsText = customWords.joined(separator: ", ")
        return "Important Vocabulary: \(wordsText)"
    }

    private func getCustomVocabularyWords() -> [String]? {
        guard let data = UserDefaults.standard.data(forKey: "CustomVocabularyItems") else {
            return nil
        }

        do {
            let items = try JSONDecoder().decode([VocabularyWord].self, from: data)
            let words = items.map { $0.word }
            return words.isEmpty ? nil : words
        } catch {
            return nil
        }
    }

    private func migrateOldDataIfNeeded() {
        // Migrate from old "CustomDictionaryItems" key to new "CustomVocabularyItems" key
        if UserDefaults.standard.data(forKey: "CustomVocabularyItems") == nil,
           let oldData = UserDefaults.standard.data(forKey: "CustomDictionaryItems") {
            UserDefaults.standard.set(oldData, forKey: "CustomVocabularyItems")
            UserDefaults.standard.removeObject(forKey: "CustomDictionaryItems")
        }
    }
}
