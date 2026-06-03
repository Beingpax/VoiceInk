import OSLog
import SwiftData

enum DictionaryService {
    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "DictionaryService")

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

    // MARK: - Duplicate Cleanup

    @discardableResult
    static func removeExactDuplicateContent(context: ModelContext, source: String) -> Bool {
        var deletedVocabularyCount = 0
        var deletedReplacementCount = 0

        if let vocabularyWords = try? context.fetch(FetchDescriptor<VocabularyWord>()) {
            var seenWords = Set<String>()

            for vocabularyWord in vocabularyWords.sorted(by: { $0.dateAdded < $1.dateAdded }) {
                let word = vocabularyWord.word
                guard !word.isEmpty else { continue }

                if seenWords.insert(word).inserted {
                    continue
                }

                context.delete(vocabularyWord)
                deletedVocabularyCount += 1
            }
        }

        if let wordReplacements = try? context.fetch(FetchDescriptor<WordReplacement>()) {
            var seenReplacements = Set<[String]>()

            for wordReplacement in wordReplacements.sorted(by: { $0.dateAdded < $1.dateAdded }) {
                let key = [wordReplacement.originalText, wordReplacement.replacementText]
                guard !wordReplacement.originalText.isEmpty || !wordReplacement.replacementText.isEmpty else {
                    continue
                }

                if seenReplacements.insert(key).inserted {
                    continue
                }

                context.delete(wordReplacement)
                deletedReplacementCount += 1
            }
        }

        guard deletedVocabularyCount > 0 || deletedReplacementCount > 0 else {
            return false
        }

        do {
            try context.save()
            logger.notice("Removed exact dictionary duplicates from \(source, privacy: .public): \(deletedVocabularyCount, privacy: .public) vocabulary, \(deletedReplacementCount, privacy: .public) word replacement")
            return true
        } catch {
            context.rollback()
            logger.error("Failed to remove exact dictionary duplicates from \(source, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
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
