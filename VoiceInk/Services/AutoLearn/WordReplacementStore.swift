import Foundation
import SwiftData

@ModelActor
actor WordReplacementStore {
    func apply(_ candidates: [LearnedReplacementCandidate]) throws -> AutoLearnMutationSummary {
        guard !candidates.isEmpty else { return .empty }

        var createdCount = 0
        var updatedCount = 0
        var movedCount = 0

        do {
            try modelContext.transaction {
                var entries = try modelContext.fetch(FetchDescriptor<WordReplacement>())

                for candidate in candidates {
                    let source = candidate.source.trimmingCharacters(in: .whitespacesAndNewlines)
                    let destination = candidate.destination.trimmingCharacters(in: .whitespacesAndNewlines)
                    let sourceKey = WordReplacementVariants.key(for: source)
                    let destinationKey = WordReplacementVariants.destinationKey(for: destination)

                    guard !source.isEmpty, !destination.isEmpty, !source.contains(","),
                        !sourceKey.isEmpty, !destinationKey.isEmpty,
                        source != destination,
                        !wouldCreateCycle(
                            sourceKey: sourceKey,
                            destinationKey: destinationKey,
                            entries: entries
                        )
                    else {
                        continue
                    }

                    let sourceWasMoved = entries.contains { entry in
                        WordReplacementVariants.destinationKey(for: entry.replacementText) != destinationKey
                            && WordReplacementVariants.contains(
                                source,
                                in: WordReplacementVariants.parse(entry.originalText)
                            )
                    }

                    let destinationMatches = entries
                        .filter {
                            WordReplacementVariants.destinationKey(for: $0.replacementText) == destinationKey
                        }
                        .sorted(by: destinationOrder)

                    let canonical = destinationMatches.first
                    var candidateChanged = false

                    if let canonical {
                        let sameStateDuplicates = destinationMatches.dropFirst().filter {
                            $0.isEnabled == canonical.isEnabled
                        }

                        for duplicate in sameStateDuplicates {
                            let merged = WordReplacementVariants.serialize(
                                WordReplacementVariants.parse(canonical.originalText)
                                    + WordReplacementVariants.parse(duplicate.originalText)
                            )
                            if canonical.originalText != merged {
                                canonical.originalText = merged
                            }

                            modelContext.delete(duplicate)
                            entries.removeAll { $0 === duplicate }
                            candidateChanged = true
                        }
                    }

                    let currentEntries = entries
                    for entry in currentEntries {
                        if let canonical, entry === canonical {
                            continue
                        }

                        let variants = WordReplacementVariants.parse(entry.originalText)
                        let remaining = variants.filter {
                            WordReplacementVariants.key(for: $0) != sourceKey
                        }
                        guard remaining.count != variants.count else { continue }

                        if remaining.isEmpty {
                            modelContext.delete(entry)
                            entries.removeAll { $0 === entry }
                        } else {
                            entry.originalText = WordReplacementVariants.serialize(remaining)
                        }
                        candidateChanged = true
                    }

                    if let canonical {
                        var variants = WordReplacementVariants.parse(canonical.originalText)
                        if !WordReplacementVariants.contains(source, in: variants) {
                            variants.append(source)
                            candidateChanged = true
                        }

                        let serialized = WordReplacementVariants.serialize(variants)
                        if canonical.originalText != serialized {
                            canonical.originalText = serialized
                            candidateChanged = true
                        }

                        if candidateChanged {
                            updatedCount += 1
                        }
                    } else {
                        let entry = WordReplacement(
                            originalText: WordReplacementVariants.serialize([source]),
                            replacementText: destination
                        )
                        modelContext.insert(entry)
                        entries.append(entry)
                        createdCount += 1
                    }

                    if sourceWasMoved {
                        movedCount += 1
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
            movedCount: movedCount
        )
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
        // Case-only formatting rules such as `voiceink -> VoiceInk` are idempotent.
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

        // The candidate moves this source away from any previous owner.
        graph.removeValue(forKey: sourceKey)

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
