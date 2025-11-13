import Foundation
import SwiftData
import OSLog

/// One-time migration service to move vocabulary and word replacement data from UserDefaults to SwiftData
class VocabularyMigrationService {
    private static let migrationCompletedKey = "VocabularySwiftDataMigrationCompleted"
    private static let vocabularyItemsKey = "CustomDictionaryItems"
    private static let wordReplacementsKey = "wordReplacements"

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "Migration")

    /// Performs one-time migration from UserDefaults to SwiftData
    /// - Parameter modelContext: The SwiftData model context to insert migrated data into
    func migrateIfNeeded(modelContext: ModelContext) {
        // Check if migration has already been completed
        guard !UserDefaults.standard.bool(forKey: Self.migrationCompletedKey) else {
            logger.info("Migration already completed, skipping")
            return
        }

        logger.info("Starting vocabulary data migration from UserDefaults to SwiftData")

        var vocabularyMigrated = 0
        var replacementsMigrated = 0
        var vocabularyMigrationSucceeded = true
        var replacementsMigrationSucceeded = true

        // Migrate vocabulary words
        if let data = UserDefaults.standard.data(forKey: Self.vocabularyItemsKey) {
            do {
                // Decode from the old Codable format
                let decoder = JSONDecoder()
                if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    // Old format: array of dictionaries with "word" key
                    for item in json {
                        if let word = item["word"] as? String,
                           !word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            // Check if this word already exists in SwiftData
                            let predicate = #Predicate<VocabularyWord> { $0.word == word }
                            let descriptor = FetchDescriptor<VocabularyWord>(predicate: predicate)

                            if let existing = try? modelContext.fetch(descriptor), existing.isEmpty {
                                let vocabularyWord = VocabularyWord(word: word)
                                modelContext.insert(vocabularyWord)
                                vocabularyMigrated += 1
                            }
                        }
                    }
                }

                try modelContext.save()
                logger.info("Migrated \(vocabularyMigrated) vocabulary words")
            } catch {
                logger.error("Failed to migrate vocabulary words: \(error.localizedDescription)")
                vocabularyMigrationSucceeded = false
            }
        }

        // Migrate word replacements
        if let replacements = UserDefaults.standard.dictionary(forKey: Self.wordReplacementsKey) as? [String: String] {
            for (originalVariants, replacement) in replacements {
                let trimmedOriginals = originalVariants.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)

                guard !trimmedOriginals.isEmpty && !trimmedReplacement.isEmpty else { continue }

                // Check if this replacement already exists in SwiftData
                let predicate = #Predicate<WordReplacement> {
                    $0.originalVariants == trimmedOriginals && $0.replacement == trimmedReplacement
                }
                let descriptor = FetchDescriptor<WordReplacement>(predicate: predicate)

                if let existing = try? modelContext.fetch(descriptor), existing.isEmpty {
                    let wordReplacement = WordReplacement(
                        originalVariants: trimmedOriginals,
                        replacement: trimmedReplacement
                    )
                    modelContext.insert(wordReplacement)
                    replacementsMigrated += 1
                }
            }

            do {
                try modelContext.save()
                logger.info("Migrated \(replacementsMigrated) word replacements")
            } catch {
                logger.error("Failed to migrate word replacements: \(error.localizedDescription)")
                replacementsMigrationSucceeded = false
            }
        }

        // Only mark migration as completed if BOTH migrations succeeded
        if vocabularyMigrationSucceeded && replacementsMigrationSucceeded {
            UserDefaults.standard.set(true, forKey: Self.migrationCompletedKey)
            logger.info("Migration completed successfully. Total: \(vocabularyMigrated) words, \(replacementsMigrated) replacements")
        } else {
            logger.error("Migration failed. Will retry on next app launch.")
        }

        // Note: We intentionally DO NOT delete the UserDefaults data here
        // This allows users to rollback if needed and serves as a backup
    }
}
