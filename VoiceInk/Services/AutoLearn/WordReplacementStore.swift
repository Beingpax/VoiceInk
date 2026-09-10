import Foundation
import SwiftData

@ModelActor
actor WordReplacementStore {
    func excludingExistingSources(
        from candidates: [LearnedReplacementCandidate]
    ) throws -> [LearnedReplacementCandidate] {
        let existingSourceKeys = Set(
            try modelContext.fetch(FetchDescriptor<WordReplacement>()).flatMap {
                WordReplacementVariants.parse($0.originalText).map {
                    WordReplacementVariants.key(for: $0)
                }
            }
        )
        return candidates.filter {
            !existingSourceKeys.contains(WordReplacementVariants.key(for: $0.source))
        }
    }

    func apply(
        _ decisions: [AutoLearnReviewDecision],
        candidates: [AutoLearnReviewCandidate]
    ) throws -> AutoLearnMutationSummary {
        guard !decisions.isEmpty else { return .empty }

        var createdCount = 0
        var updatedCount = 0
        var vocabularyCount = 0
        var learnedCorrections: [AutoLearnAppliedCorrection] = []

        do {
            try modelContext.transaction {
                var entries = try modelContext.fetch(FetchDescriptor<WordReplacement>())
                var existingSourceKeys = Set(
                    entries.flatMap {
                        WordReplacementVariants.parse($0.originalText).map {
                            WordReplacementVariants.key(for: $0)
                        }
                    }
                )
                var vocabularyKeys = Set(
                    try modelContext.fetch(FetchDescriptor<VocabularyWord>()).map {
                        WordReplacementVariants.key(for: $0.word)
                    }
                )
                let candidatesByID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })

                for decision in decisions {
                    guard decision.accepted,
                        let candidate = candidatesByID[decision.id]
                    else { continue }

                    let mutation = applyReplacement(
                        source: candidate.source,
                        destination: candidate.destination,
                        entries: &entries,
                        existingSourceKeys: &existingSourceKeys
                    )
                    createdCount += mutation.created ? 1 : 0
                    updatedCount += mutation.updated ? 1 : 0

                    let vocabulary = candidate.destination.trimmingCharacters(in: .whitespacesAndNewlines)
                    let vocabularyKey = WordReplacementVariants.key(for: vocabulary)
                    var vocabularyCreationDate: Date?
                    if !vocabularyKey.isEmpty, vocabularyKeys.insert(vocabularyKey).inserted {
                        let entry = VocabularyWord(word: vocabulary)
                        modelContext.insert(entry)
                        vocabularyCreationDate = entry.dateAdded
                        vocabularyCount += 1
                    }

                    if mutation.created || mutation.updated || vocabularyCreationDate != nil {
                        learnedCorrections.append(
                            AutoLearnAppliedCorrection(
                                source: candidate.source,
                                destination: candidate.destination,
                                replacementWasChanged: mutation.created || mutation.updated,
                                vocabularyCreationDate: vocabularyCreationDate
                            )
                        )
                    }
                }
            }
        } catch {
            modelContext.rollback()
            throw error
        }

        return AutoLearnMutationSummary(
            createdCount: createdCount,
            updatedCount: updatedCount,
            vocabularyCount: vocabularyCount,
            learnedCorrections: learnedCorrections
        )
    }

    func undo(_ correction: AutoLearnAppliedCorrection) throws {
        try modelContext.transaction {
            if correction.replacementWasChanged {
                let destinationKey = WordReplacementVariants.destinationKey(for: correction.destination)
                let entries = try modelContext.fetch(FetchDescriptor<WordReplacement>())
                if let entry = entries.first(where: {
                    WordReplacementVariants.destinationKey(for: $0.replacementText) == destinationKey
                        && WordReplacementVariants.contains(
                            correction.source,
                            in: WordReplacementVariants.parse($0.originalText)
                        )
                }) {
                    var variants = WordReplacementVariants.parse(entry.originalText)
                    variants.removeAll {
                        WordReplacementVariants.key(for: $0)
                            == WordReplacementVariants.key(for: correction.source)
                    }
                    if variants.isEmpty {
                        modelContext.delete(entry)
                    } else {
                        entry.originalText = WordReplacementVariants.serialize(variants)
                    }
                }
            }

            if let creationDate = correction.vocabularyCreationDate {
                let vocabularyKey = WordReplacementVariants.key(for: correction.destination)
                let vocabulary = try modelContext.fetch(FetchDescriptor<VocabularyWord>())
                if let entry = vocabulary.first(where: {
                    $0.dateAdded == creationDate
                        && WordReplacementVariants.key(for: $0.word) == vocabularyKey
                }) {
                    modelContext.delete(entry)
                }
            }
        }
    }

    private func applyReplacement(
        source rawSource: String,
        destination rawDestination: String,
        entries: inout [WordReplacement],
        existingSourceKeys: inout Set<String>
    ) -> (created: Bool, updated: Bool) {
        let source = rawSource.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = rawDestination.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceKey = WordReplacementVariants.key(for: source)
        let destinationKey = WordReplacementVariants.destinationKey(for: destination)

        guard !source.isEmpty, !destination.isEmpty, !source.contains(","),
            !sourceKey.isEmpty, !destinationKey.isEmpty,
            source != destination,
            !existingSourceKeys.contains(sourceKey),
            !wouldCreateCycle(sourceKey: sourceKey, destinationKey: destinationKey, entries: entries)
        else {
            return (false, false)
        }

        let destinationMatches = entries
            .filter {
                $0.isEnabled
                    && WordReplacementVariants.destinationKey(for: $0.replacementText) == destinationKey
            }
            .sorted(by: destinationOrder)
        let canonical = destinationMatches.first
        var changed = false

        if let canonical {
            for duplicate in destinationMatches.dropFirst() {
                let merged = WordReplacementVariants.serialize(
                    WordReplacementVariants.parse(canonical.originalText)
                        + WordReplacementVariants.parse(duplicate.originalText)
                )
                if canonical.originalText != merged {
                    canonical.originalText = merged
                }
                modelContext.delete(duplicate)
                entries.removeAll { $0 === duplicate }
                changed = true
            }

            var variants = WordReplacementVariants.parse(canonical.originalText)
            if !WordReplacementVariants.contains(source, in: variants) {
                variants.append(source)
                changed = true
            }
            let serialized = WordReplacementVariants.serialize(variants)
            if canonical.originalText != serialized {
                canonical.originalText = serialized
                changed = true
            }
        } else {
            let entry = WordReplacement(
                originalText: WordReplacementVariants.serialize([source]),
                replacementText: destination
            )
            modelContext.insert(entry)
            entries.append(entry)
        }

        existingSourceKeys.insert(sourceKey)
        return (canonical == nil, canonical != nil && changed)
    }

    private func destinationOrder(_ lhs: WordReplacement, _ rhs: WordReplacement) -> Bool {
        if lhs.isEnabled != rhs.isEnabled {
            return lhs.isEnabled && !rhs.isEnabled
        }
        if lhs.dateAdded != rhs.dateAdded {
            return lhs.dateAdded < rhs.dateAdded
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func wouldCreateCycle(
        sourceKey: String,
        destinationKey: String,
        entries: [WordReplacement]
    ) -> Bool {
        guard sourceKey != destinationKey else { return false }

        var graph: [String: String] = [:]
        for entry in entries.sorted(by: destinationOrder) {
            let next = WordReplacementVariants.destinationKey(for: entry.replacementText)
            guard !next.isEmpty else { continue }

            for variant in WordReplacementVariants.parse(entry.originalText) {
                let key = WordReplacementVariants.key(for: variant)
                guard !key.isEmpty, graph[key] == nil else { continue }
                graph[key] = next
            }
        }

        var current = destinationKey
        var visited = Set<String>()
        while visited.insert(current).inserted, let next = graph[current] {
            if next == sourceKey {
                return true
            }
            if next == current {
                return false
            }
            current = next
        }

        return false
    }
}
