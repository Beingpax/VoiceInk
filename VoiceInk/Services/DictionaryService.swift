import SwiftData

enum DictionaryService {

    // MARK: - Vocabulary

    /// Adds one or more comma-separated words to vocabulary.
    /// Returns an error message string if something went wrong, nil on success.
    @discardableResult
    static func addVocabularyWords(
        _ input: String,
        existing: [VocabularyWord],
        context: ModelContext
    ) -> String? {
        let parts = input
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else { return nil }

        if parts.count == 1, let word = parts.first {
            if existing.contains(where: { $0.word.lowercased() == word.lowercased() }) {
                return "'\(word)' is already in the vocabulary"
            }
            return insertVocabularyWord(word, context: context)
        }

        var addedWords = Set(existing.map { $0.word.lowercased() })
        var errors = [String]()
        for word in parts {
            let lower = word.lowercased()
            if !addedWords.contains(lower) {
                if let error = insertVocabularyWord(word, context: context) {
                    errors.append(error)
                }
                addedWords.insert(lower)
            }
        }
        return errors.isEmpty ? nil : errors.joined(separator: "; ")
    }

    @discardableResult
    private static func insertVocabularyWord(_ word: String, context: ModelContext) -> String? {
        let entry = VocabularyWord(word: word)
        context.insert(entry)
        do {
            try context.save()
            return nil
        } catch {
            context.delete(entry)
            return "Failed to add '\(word)': \(error.localizedDescription)"
        }
    }

    // MARK: - Word Replacement

    /// Adds a word replacement entry (original may be comma-separated).
    /// Returns an error message string if something went wrong, nil on success.
    @discardableResult
    static func addWordReplacement(
        original: String,
        replacement: String,
        existing: [WordReplacement],
        context: ModelContext
    ) -> String? {
        let tokens = original
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty, !replacement.isEmpty else { return nil }

        for existingEntry in existing {
            let existingTokens = existingEntry.originalText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }

            for token in tokens {
                if existingTokens.contains(token.lowercased()) {
                    return "'\(token)' already exists in word replacements"
                }
            }
        }

        let entry = WordReplacement(originalText: original, replacementText: replacement)
        context.insert(entry)
        do {
            try context.save()
            return nil
        } catch {
            context.delete(entry)
            return "Failed to add replacement: \(error.localizedDescription)"
        }
    }
}
