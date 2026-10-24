import Foundation
import SwiftData

@ModelActor
actor WordReplacementStore {
    private enum MutationError: Error { case invalidReplacementSource }

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

    func apply(
        _ decisions: [AutoLearnReviewDecision],
        candidates: [AutoLearnReviewCandidate]
    ) throws -> AutoLearnMutationSummary {
        try Task.checkCancellation()
        guard !decisions.isEmpty else { return .empty }

        var createdCount = 0
        var updatedCount = 0

        do {
            try modelContext.transaction {
                var entries = try modelContext.fetch(FetchDescriptor<WordReplacement>())
                var existingSourceKeys = Set(entries.flatMap {
                    WordReplacementVariants.parse($0.originalText).map { WordReplacementVariants.key(for: $0) }
                })
                let candidateIDs = Set(candidates.map(\.candidateID))
                for decision in decisions {
                    try Task.checkCancellation()
                    guard candidateIDs.contains(decision.candidateID),
                        decision.learningAction == .addReplacementOnly,
                        let source = decision.incorrectTextToReplace,
                        let destination = decision.correctedVocabularyTerm,
                        AutoLearnLocalReviewPolicy.accepts(source: source, destination: destination)
                    else { continue }

                    let mutation = try applyReplacement(
                        source: source,
                        destination: destination,
                        entries: &entries,
                        existingSourceKeys: &existingSourceKeys)
                    createdCount += mutation.created ? 1 : 0
                    updatedCount += mutation.updated ? 1 : 0
                }
                try Task.checkCancellation()
            }
            try Task.checkCancellation()
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }

        return AutoLearnMutationSummary(
            createdCount: createdCount,
            updatedCount: updatedCount)
    }

    private func applyReplacement(
        source rawSource: String,
        destination rawDestination: String,
        entries: inout [WordReplacement],
        existingSourceKeys: inout Set<String>
    ) throws -> (created: Bool, updated: Bool) {
        let source = rawSource.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        let destination = rawDestination.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        let sourceKey = WordReplacementVariants.key(for: source)
        let destinationKey = WordReplacementVariants.destinationKey(for: destination)
        let destinationSourceKey = WordReplacementVariants.key(for: destination)

        guard !source.contains(",") else { throw MutationError.invalidReplacementSource }
        guard !source.isEmpty, !destination.isEmpty,
            !sourceKey.isEmpty, !destinationKey.isEmpty,
            source != destination,
            !existingSourceKeys.contains(sourceKey),
            !wouldCreateCycle(
                sourceKey: sourceKey,
                destinationSourceKey: destinationSourceKey,
                entries: entries
            )
        else {
            return (false, false)
        }

        let destinationMatches = entries
            .filter {
                WordReplacementVariants.destinationKey(for: $0.replacementText) == destinationKey
            }
            .sorted(by: destinationOrder)
        let canonical = destinationMatches.first

        if let canonical {
            var variants = WordReplacementVariants.parse(canonical.originalText)
            variants.append(source)
            canonical.originalText = WordReplacementVariants.serialize(variants)
        } else {
            let entry = WordReplacement(
                originalText: WordReplacementVariants.serialize([source]),
                replacementText: destination
            )
            modelContext.insert(entry)
            entries.append(entry)
        }

        existingSourceKeys.insert(sourceKey)
        return (canonical == nil, canonical != nil)
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
