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
        word.sectionID = sectionID
        do {
            try context.save()
            return nil
        } catch {
            context.rollback()
            return error.localizedDescription
        }
    }

    static func delete(_ section: VocabularySection, words: [VocabularyWord], context: ModelContext) -> String? {
        for word in words where word.sectionID == section.id {
            word.sectionID = nil
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
