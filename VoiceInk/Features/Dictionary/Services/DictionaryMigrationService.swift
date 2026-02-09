import Foundation
import SwiftData
import OSLog

class DictionaryMigrationService {
    static let shared = DictionaryMigrationService()
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "DictionaryMigration")

    private let migrationCompletedKey = "HasMigratedDictionaryToSwiftData_v2"
    private let vocabularyKey = "CustomVocabularyItems"
    private let wordReplacementsKey = "wordReplacements"

    private init() {}

    /// Migrates dictionary data from UserDefaults to SwiftData
    /// This is a one-time operation that preserves all existing user data
    func migrateIfNeeded(context: ModelContext) {
        // Check if migration has already been completed
        if UserDefaults.standard.bool(forKey: migrationCompletedKey) {
            logger.info("Dictionary migration already completed, skipping")
            return
        }

        logger.info("Starting dictionary migration from UserDefaults to SwiftData")

        var vocabularyMigrated = 0
        var replacementsMigrated = 0

        // Migrate vocabulary words
        if let data = UserDefaults.standard.data(forKey: vocabularyKey) {
            do {
                // Decode old vocabulary structure
                let decoder = JSONDecoder()
                let oldVocabulary = try decoder.decode([OldVocabularyWord].self, from: data)

                logger.info("Found \(oldVocabulary.count) vocabulary words to migrate")

                for oldWord in oldVocabulary {
                    let newWord = VocabularyWord(word: oldWord.word)
                    context.insert(newWord)
                    vocabularyMigrated += 1
                }

                logger.info("Successfully migrated \(vocabularyMigrated) vocabulary words")
            } catch {
                logger.error("Failed to migrate vocabulary words: \(error.localizedDescription)")
            }
        } else {
            logger.info("No vocabulary words found to migrate")
        }

        // Migrate word replacements
        if let replacements = UserDefaults.standard.dictionary(forKey: wordReplacementsKey) as? [String: String] {
            logger.info("Found \(replacements.count) word replacements to migrate")

            for (originalText, replacementText) in replacements {
                let wordReplacement = WordReplacement(
                    originalText: originalText,
                    replacementText: replacementText
                )
                context.insert(wordReplacement)
                replacementsMigrated += 1
            }

            logger.info("Successfully migrated \(replacementsMigrated) word replacements")
        } else {
            logger.info("No word replacements found to migrate")
        }

        // Save the migrated data
        do {
            try context.save()
            logger.info("Successfully saved migrated data to SwiftData")

            // Mark migration as completed
            UserDefaults.standard.set(true, forKey: migrationCompletedKey)
            logger.info("Migration completed successfully")
        } catch {
            logger.error("Failed to save migrated data: \(error.localizedDescription)")
        }
    }
}

// Legacy structure for decoding old vocabulary data
private struct OldVocabularyWord: Decodable {
    let word: String

    private enum CodingKeys: String, CodingKey {
        case id, word, dateAdded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        word = try container.decode(String.self, forKey: .word)
        // Ignore other fields that may exist in old format
        _ = try? container.decodeIfPresent(UUID.self, forKey: .id)
        _ = try? container.decodeIfPresent(Date.self, forKey: .dateAdded)
    }
}
