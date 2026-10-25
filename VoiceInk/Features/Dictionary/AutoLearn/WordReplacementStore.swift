import Foundation
import SwiftData

@ModelActor
actor WordReplacementStore {
    private enum ApplyError: LocalizedError {
        case conflictingReplacement

        var errorDescription: String? {
            String(localized: "These corrections conflict with existing word replacements. Review your dictionary and try again.")
        }
    }

    func unsavedSuggestions(_ suggestions: [AutoLearnReviewDecision]) throws -> [AutoLearnReviewDecision] {
        guard !suggestions.isEmpty else { return [] }
        let entries = try modelContext.fetch(FetchDescriptor<WordReplacement>())
        let savedSources = Set(entries.flatMap {
            WordReplacementVariants.parse($0.originalText).map { WordReplacementVariants.key(for: $0) }
        })
        return suggestions.filter { suggestion in
            guard let source = suggestion.incorrectTextToReplace,
                let destination = suggestion.correctedVocabularyTerm else { return false }
            let sourceKey = WordReplacementVariants.key(for: source)
            return !savedSources.contains(sourceKey)
                && !wouldCreateCycle(sourceKey: sourceKey,
                    destinationSourceKey: WordReplacementVariants.key(for: destination), entries: entries)
        }
    }

    func apply(_ suggestion: AutoLearnSuggestion) throws -> Bool {
        try Task.checkCancellation()
        guard suggestion.isValid else { return false }

        var hasChanges = false
        do {
            try modelContext.transaction {
                let entries = try modelContext.fetch(FetchDescriptor<WordReplacement>())
                try Task.checkCancellation()
                hasChanges = try applyReplacement(sources: suggestion.originals.map(\.text),
                    destination: suggestion.replacementText, entries: entries)
                try Task.checkCancellation()
            }
            try Task.checkCancellation()
            if hasChanges { try modelContext.save() }
        } catch {
            modelContext.rollback()
            throw error
        }
        return hasChanges
    }

    private func applyReplacement(
        sources: [String],
        destination rawDestination: String,
        entries: [WordReplacement]
    ) throws -> Bool {
        let destination = WordReplacementVariants.destinationKey(for: rawDestination)
        let destinationSourceKey = WordReplacementVariants.key(for: destination)
        let orderedEntries = entries.sorted(by: destinationOrder)
        var savedDestinations: [String: Set<String>] = [:]
        for entry in orderedEntries {
            for source in WordReplacementVariants.parse(entry.originalText) {
                savedDestinations[WordReplacementVariants.key(for: source), default: []]
                    .insert(WordReplacementVariants.destinationKey(for: entry.replacementText))
            }
        }

        var newSources: [String] = []
        var seen = Set<String>()
        for source in sources {
            let key = WordReplacementVariants.key(for: source)
            guard seen.insert(key).inserted else { continue }
            if let destinations = savedDestinations[key] {
                guard destinations == Set([destination]) else { throw ApplyError.conflictingReplacement }
            } else {
                newSources.append(source)
            }
        }
        guard !newSources.isEmpty else { return false }
        guard !WordReplacementVariants.wouldCreateCycle(
            newSources: newSources.map {
                (source: WordReplacementVariants.key(for: $0), destination: destinationSourceKey)
            },
            in: orderedEntries.map { (originalText: $0.originalText, replacementText: $0.replacementText) }
        ) else { throw ApplyError.conflictingReplacement }

        if let canonical = orderedEntries.first(where: {
            WordReplacementVariants.destinationKey(for: $0.replacementText) == destination
        }) {
            canonical.originalText = WordReplacementVariants.serialize(
                WordReplacementVariants.parse(canonical.originalText) + newSources)
        } else {
            modelContext.insert(WordReplacement(
                originalText: WordReplacementVariants.serialize(newSources), replacementText: destination))
        }
        return true
    }

    private func destinationOrder(_ lhs: WordReplacement, _ rhs: WordReplacement) -> Bool {
        if lhs.dateAdded != rhs.dateAdded {
            return lhs.dateAdded < rhs.dateAdded
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func wouldCreateCycle(
        sourceKey: String,
        destinationSourceKey: String,
        entries: [WordReplacement]
    ) -> Bool {
        WordReplacementVariants.wouldCreateCycle(
            newSources: [(source: sourceKey, destination: destinationSourceKey)],
            in: entries
                .sorted(by: destinationOrder)
                .map { (originalText: $0.originalText, replacementText: $0.replacementText) }
        )
    }
}
