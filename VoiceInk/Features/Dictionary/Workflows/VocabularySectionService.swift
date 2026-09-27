import Foundation
import SwiftData

enum VocabularySectionService {
    static func save(
        _ section: VocabularySection?,
        name: String,
        description: String,
        existing: [VocabularySection],
        context: ModelContext
    ) -> String? {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return String(localized: "Enter a section name.") }
        guard !existing.contains(where: {
            $0.id != section?.id && $0.name.compare(normalizedName, options: .caseInsensitive) == .orderedSame
        }) else {
            return String(localized: "A section with this name already exists.")
        }

        if let section {
            section.name = normalizedName
            section.sectionDescription = normalizedDescription
        } else {
            context.insert(VocabularySection(name: normalizedName, sectionDescription: normalizedDescription))
        }

        do {
            try context.save()
            return nil
        } catch {
            context.rollback()
            return error.localizedDescription
        }
    }

    static func move(_ word: VocabularyWord, to sectionID: UUID?, context: ModelContext) -> String? {
        guard word.sectionID != sectionID else { return nil }
        do {
            let identity = VocabularyWordIdentity(word: word.word, sectionID: sectionID)
            let words = try context.fetch(
                FetchDescriptor<VocabularyWord>(predicate: #Predicate { $0.sectionID == sectionID })
            )
            guard !words.contains(where: {
                $0 !== word && VocabularyWordIdentity(word: $0.word, sectionID: $0.sectionID) == identity
            }) else {
                return DictionaryService.duplicateVocabularyMessage(word.word, sectionID: sectionID)
            }

            word.sectionID = sectionID
            try context.save()
            return nil
        } catch {
            context.rollback()
            return error.localizedDescription
        }
    }

    static func delete(_ section: VocabularySection, words: [VocabularyWord], context: ModelContext) -> String? {
        var unsectionedWords = Set(
            words.lazy
                .filter { $0.sectionID == nil }
                .map { VocabularyWordIdentity(word: $0.word, sectionID: nil) }
        )
        for word in words where word.sectionID == section.id {
            let identity = VocabularyWordIdentity(word: word.word, sectionID: nil)
            if unsectionedWords.insert(identity).inserted {
                word.sectionID = nil
            } else {
                context.delete(word)
            }
        }
        context.delete(section)
        do {
            try context.save()
            return nil
        } catch {
            context.rollback()
            return error.localizedDescription
        }
    }
}
