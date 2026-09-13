import Foundation
import SwiftData

@ModelActor
actor WordReplacementStore {
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
                let candidatesByID = Dictionary(
                    uniqueKeysWithValues: candidates.map { ($0.candidateID, $0) }
                )

                for decision in decisions {
                    guard let candidate = candidatesByID[decision.candidateID],
                        decision.learningAction != .rejectCorrection,
                        let correctedVocabularyTerm = decision.correctedVocabularyTerm
                    else { continue }

                    let mutation: (created: Bool, updated: Bool)
                    let shouldAddVocabulary: Bool
                    switch decision.learningAction {
                    case .addReplacementAndVocabulary:
                        shouldAddVocabulary = true
                        guard let incorrectTextToReplace = decision.incorrectTextToReplace else {
                            continue
                        }
                        mutation = applyReplacement(
                            source: incorrectTextToReplace,
                            destination: correctedVocabularyTerm,
                            entries: &entries,
                            existingSourceKeys: &existingSourceKeys
                        )
                    case .addReplacementOnly:
                        shouldAddVocabulary = false
                        guard let incorrectTextToReplace = decision.incorrectTextToReplace else {
                            continue
                        }
                        mutation = applyReplacement(
                            source: incorrectTextToReplace,
                            destination: correctedVocabularyTerm,
                            entries: &entries,
                            existingSourceKeys: &existingSourceKeys
                        )
                    case .addVocabularyOnly:
                        shouldAddVocabulary = true
                        mutation = (false, false)
                    case .rejectCorrection:
                        continue
                    }
                    createdCount += mutation.created ? 1 : 0
                    updatedCount += mutation.updated ? 1 : 0

                    let vocabulary = correctedVocabularyTerm
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .precomposedStringWithCanonicalMapping
                    let vocabularyKey = WordReplacementVariants.key(for: vocabulary)
                    var vocabularyCreationDate: Date?
                    if shouldAddVocabulary,
                        !vocabularyKey.isEmpty,
                        vocabularyKeys.insert(vocabularyKey).inserted
                    {
                        let entry = VocabularyWord(word: vocabulary)
                        modelContext.insert(entry)
                        vocabularyCreationDate = entry.dateAdded
                        vocabularyCount += 1
                    }

                    if mutation.created || mutation.updated || vocabularyCreationDate != nil {
                        learnedCorrections.append(
                            AutoLearnAppliedCorrection(
                                incorrectTextToReplace: decision.incorrectTextToReplace
                                    ?? candidate.originalText,
                                correctedVocabularyTerm: correctedVocabularyTerm,
                                replacementSourceWasAdded: mutation.created || mutation.updated,
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
            if correction.replacementSourceWasAdded {
                let destinationKey = WordReplacementVariants.destinationKey(
                    for: correction.correctedVocabularyTerm
                )
                let entries = try modelContext.fetch(FetchDescriptor<WordReplacement>())
                if let entry = entries.first(where: {
                    WordReplacementVariants.destinationKey(for: $0.replacementText) == destinationKey
                        && WordReplacementVariants.contains(
                            correction.incorrectTextToReplace,
                            in: WordReplacementVariants.parse($0.originalText)
                        )
                }) {
                    var variants = WordReplacementVariants.parse(entry.originalText)
                    variants.removeAll {
                        WordReplacementVariants.key(for: $0)
                            == WordReplacementVariants.key(
                                for: correction.incorrectTextToReplace
                            )
                    }
                    if variants.isEmpty {
                        modelContext.delete(entry)
                    } else {
                        entry.originalText = WordReplacementVariants.serialize(variants)
                    }
                }
            }

            if let creationDate = correction.vocabularyCreationDate {
                let vocabularyKey = WordReplacementVariants.key(
                    for: correction.correctedVocabularyTerm
                )
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
            .precomposedStringWithCanonicalMapping
        let destination = rawDestination.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        let sourceKey = WordReplacementVariants.key(for: source)
        let destinationKey = WordReplacementVariants.destinationKey(for: destination)
        let destinationSourceKey = WordReplacementVariants.key(for: destination)

        guard !source.isEmpty, !destination.isEmpty, !source.contains(","),
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
            // Auto Learn only adds the learned source without rewriting rows,
            // allowing Undo to remove exactly what was added.
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
