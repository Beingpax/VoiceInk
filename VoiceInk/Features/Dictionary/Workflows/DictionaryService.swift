import Foundation
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
        let parts =
            input
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else { return nil }

        if parts.count == 1, let word = parts.first {
            if existing.contains(where: { $0.word.lowercased() == word.lowercased() }) {
                return String(format: String(localized: "'%@' is already in the vocabulary"), word)
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
            return String(format: String(localized: "Failed to add '%@': %@"), word, error.localizedDescription)
        }
    }

    @discardableResult
    static func removeVocabularyWord(_ word: VocabularyWord, context: ModelContext) -> String? {
        context.delete(word)
        do {
            try context.save()
            return nil
        } catch {
            context.rollback()
            return String(
                format: String(localized: "Failed to remove word: %@"),
                error.localizedDescription
            )
        }
    }

    // MARK: - Dictionary Cleanup

    @discardableResult
    static func removeExactDuplicateContent(context: ModelContext, source: String) -> Bool {
        var deletedVocabularyCount = 0
        var deletedReplacementCount = 0
        var normalizedReplacementCount = 0

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
                let normalizedOriginal = WordReplacementVariants.serialize(
                    WordReplacementVariants.parse(wordReplacement.originalText)
                )
                let normalizedDestination = wordReplacement.replacementText
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .precomposedStringWithCanonicalMapping

                if wordReplacement.originalText != normalizedOriginal
                    || wordReplacement.replacementText != normalizedDestination
                    || !wordReplacement.isEnabled
                {
                    wordReplacement.originalText = normalizedOriginal
                    wordReplacement.replacementText = normalizedDestination
                    wordReplacement.isEnabled = true
                    normalizedReplacementCount += 1
                }

                let key = [normalizedOriginal, normalizedDestination]
                guard !normalizedOriginal.isEmpty || !normalizedDestination.isEmpty else {
                    continue
                }

                if seenReplacements.insert(key).inserted {
                    continue
                }

                context.delete(wordReplacement)
                deletedReplacementCount += 1
            }
        }

        guard normalizedReplacementCount > 0
            || deletedVocabularyCount > 0
            || deletedReplacementCount > 0
        else {
            return false
        }

        do {
            try context.save()
            logger.notice(
                "Cleaned dictionary data from \(source, privacy: .public): normalized=\(normalizedReplacementCount, privacy: .public) replacements, removed=\(deletedVocabularyCount, privacy: .public) vocabulary and \(deletedReplacementCount, privacy: .public) replacements"
            )
            return true
        } catch {
            context.rollback()
            logger.error(
                "Failed to clean dictionary data from \(source, privacy: .public): \(error, privacy: .public)"
            )
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
        let tokens = WordReplacementVariants.parse(original)

        let destination = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        guard !tokens.isEmpty, !destination.isEmpty else { return nil }

        let destinationKey = WordReplacementVariants.destinationKey(for: destination)

        for existingEntry in existing {
            let existingTokens = WordReplacementVariants.parse(existingEntry.originalText)

            for token in tokens {
                if WordReplacementVariants.contains(token, in: existingTokens),
                    WordReplacementVariants.destinationKey(for: existingEntry.replacementText)
                        != destinationKey
                {
                    return String(format: String(localized: "'%@' already exists in word replacements"), token)
                }
            }
        }

        let destinationMatches = existing
            .filter {
                WordReplacementVariants.destinationKey(for: $0.replacementText) == destinationKey
            }
            .sorted {
                if $0.dateAdded != $1.dateAdded { return $0.dateAdded < $1.dateAdded }
                return $0.id.uuidString < $1.id.uuidString
            }
        let insertedEntry: WordReplacement?
        if let canonical = destinationMatches.first {
            canonical.originalText = WordReplacementVariants.serialize(
                destinationMatches.flatMap {
                    WordReplacementVariants.parse($0.originalText)
                } + tokens
            )
            canonical.replacementText = destination
            canonical.isEnabled = true
            for duplicate in destinationMatches.dropFirst() {
                context.delete(duplicate)
            }
            insertedEntry = nil
        } else {
            let entry = WordReplacement(
                originalText: WordReplacementVariants.serialize(tokens),
                replacementText: destination
            )
            context.insert(entry)
            insertedEntry = entry
        }
        do {
            try context.save()
            return nil
        } catch {
            if let insertedEntry {
                context.delete(insertedEntry)
            } else {
                context.rollback()
            }
            return String(format: String(localized: "Failed to add replacement: %@"), error.localizedDescription)
        }
    }

    /// Updates an existing replacement and consolidates rows with the same
    /// case-sensitive, normalized destination.
    @discardableResult
    static func updateWordReplacement(
        _ replacement: WordReplacement,
        original: String,
        replacementText: String,
        context: ModelContext
    ) -> String? {
        let tokens = WordReplacementVariants.parse(original)
        let destination = replacementText.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        guard !tokens.isEmpty, !destination.isEmpty else { return nil }

        let existing: [WordReplacement]
        do {
            existing = try context.fetch(FetchDescriptor<WordReplacement>())
        } catch {
            return String(localized: "Failed to load word replacements")
        }

        let destinationKey = WordReplacementVariants.destinationKey(for: destination)
        let otherReplacements = existing.filter {
            $0.persistentModelID != replacement.persistentModelID
        }

        for existingEntry in otherReplacements {
            let existingTokens = WordReplacementVariants.parse(existingEntry.originalText)
            for token in tokens {
                if WordReplacementVariants.contains(token, in: existingTokens),
                    WordReplacementVariants.destinationKey(for: existingEntry.replacementText)
                        != destinationKey
                {
                    return String(
                        format: String(localized: "'%@' already exists in word replacements"),
                        token
                    )
                }
            }
        }

        let destinationMatches = otherReplacements
            .filter {
                WordReplacementVariants.destinationKey(for: $0.replacementText) == destinationKey
            }
            .sorted(by: replacementOrder)
        if let canonical = destinationMatches.first {
            canonical.originalText = WordReplacementVariants.serialize(
                destinationMatches.flatMap {
                    WordReplacementVariants.parse($0.originalText)
                } + tokens
            )
            canonical.replacementText = destination
            canonical.isEnabled = true
            context.delete(replacement)
            for duplicate in destinationMatches.dropFirst() {
                context.delete(duplicate)
            }
        } else {
            replacement.originalText = WordReplacementVariants.serialize(tokens)
            replacement.replacementText = destination
            replacement.isEnabled = true
        }

        do {
            try context.save()
            return nil
        } catch {
            context.rollback()
            return String(
                format: String(localized: "Failed to save changes: %@"),
                error.localizedDescription
            )
        }
    }

    @discardableResult
    static func removeWordReplacement(_ replacement: WordReplacement, context: ModelContext) -> String? {
        context.delete(replacement)
        do {
            try context.save()
            return nil
        } catch {
            context.rollback()
            return String(
                format: String(localized: "Failed to remove replacement: %@"),
                error.localizedDescription
            )
        }
    }

    private static func replacementOrder(_ lhs: WordReplacement, _ rhs: WordReplacement) -> Bool {
        if lhs.dateAdded != rhs.dateAdded { return lhs.dateAdded < rhs.dateAdded }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
