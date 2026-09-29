import Foundation
import SwiftData

enum DictionaryImportExportService {
    @MainActor
    static func preview(
        _ payload: DictionaryImportPayload,
        mode: DictionaryImportMode,
        modelContext: ModelContext
    ) async throws -> DictionaryImportSummary {
        let snapshot = try makeSnapshot(modelContext: modelContext)
        let plan = try await makePlan(
            archive: payload.archive,
            mode: mode,
            snapshot: snapshot
        )
        return plan.summary
    }

    // MARK: - Import

    @MainActor
    static func apply(
        archive: DictionaryArchive,
        mode: DictionaryImportMode,
        modelContext: ModelContext
    ) async throws -> DictionaryImportResult {
        var snapshot = try makeSnapshot(modelContext: modelContext)
        var plan = try await makePlan(archive: archive, mode: mode, snapshot: snapshot)

        // Cloud sync can update the model context while planning runs off the
        // main actor. Re-plan once against the latest snapshot when needed.
        let latestSnapshot = try makeSnapshot(modelContext: modelContext)
        if latestSnapshot != snapshot {
            snapshot = latestSnapshot
            plan = try await makePlan(archive: archive, mode: mode, snapshot: snapshot)
            guard try makeSnapshot(modelContext: modelContext) == snapshot else {
                throw DictionaryArchiveError.dictionaryChanged
            }
        }

        guard mode != .replace || plan.summary.hasImportableEntries else {
            throw DictionaryArchiveError.noImportableEntries
        }

        let existingVocabulary = try modelContext.fetch(FetchDescriptor<VocabularyWord>())
        let existingReplacements = try modelContext.fetch(FetchDescriptor<WordReplacement>())

        if mode == .replace {
            for item in existingVocabulary {
                modelContext.delete(item)
            }
            for item in existingReplacements {
                modelContext.delete(item)
            }
        }

        var replacementsByDestination: [String: [WordReplacement]] = [:]
        if mode == .merge {
            for item in existingReplacements {
                let key = WordReplacementVariants.destinationKey(for: item.replacementText)
                replacementsByDestination[key, default: []].append(item)
            }
            for key in Array(replacementsByDestination.keys) {
                replacementsByDestination[key]?.sort {
                    if $0.dateAdded != $1.dateAdded { return $0.dateAdded < $1.dateAdded }
                    return $0.id.uuidString < $1.id.uuidString
                }
            }
        }

        for entry in plan.vocabulary {
            modelContext.insert(
                VocabularyWord(word: entry.term, dateAdded: entry.createdAt ?? Date())
            )
        }

        for entry in plan.replacements {
            let destinationKey = WordReplacementVariants.destinationKey(for: entry.replacement)
            let destinationMatches = replacementsByDestination[destinationKey] ?? []

            if let canonical = destinationMatches.first {
                canonical.originalText = WordReplacementVariants.serialize(
                    destinationMatches.flatMap {
                        WordReplacementVariants.parse($0.originalText)
                    } + entry.sources
                )
                canonical.replacementText = entry.replacement

                for duplicate in destinationMatches.dropFirst() {
                    modelContext.delete(duplicate)
                }
                replacementsByDestination[destinationKey] = [canonical]
            } else {
                let replacement = WordReplacement(
                    originalText: WordReplacementVariants.serialize(entry.sources),
                    replacementText: entry.replacement,
                    dateAdded: entry.createdAt ?? Date()
                )
                modelContext.insert(replacement)
                replacementsByDestination[destinationKey] = [replacement]
            }
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DictionaryArchiveError.saveFailed(error)
        }

        return DictionaryImportResult(summary: plan.summary)
    }

    @MainActor
    static func makeArchive(modelContext: ModelContext) throws -> DictionaryArchive {
        let vocabulary = try modelContext.fetch(FetchDescriptor<VocabularyWord>())
        let replacements = try modelContext.fetch(FetchDescriptor<WordReplacement>())

        var seenVocabulary = Set<String>()
        let vocabularyEntries = vocabulary
            .sorted {
                if $0.dateAdded != $1.dateAdded { return $0.dateAdded < $1.dateAdded }
                return vocabularyKey($0.word) < vocabularyKey($1.word)
            }
            .compactMap { item -> DictionaryVocabularyEntry? in
                let term = normalizedText(item.word)
                let key = vocabularyKey(term)
                guard !term.isEmpty, seenVocabulary.insert(key).inserted else { return nil }
                return DictionaryVocabularyEntry(term: term, createdAt: item.dateAdded)
            }

        struct ReplacementGroup {
            var sources: [String]
            let replacement: String
            var createdAt: Date
        }

        var groups: [String: ReplacementGroup] = [:]
        for item in replacements.sorted(by: { $0.dateAdded < $1.dateAdded }) {
            let destination = WordReplacementVariants.destinationKey(for: item.replacementText)
            let sources = WordReplacementVariants.parse(item.originalText)
            guard !destination.isEmpty, !sources.isEmpty else { continue }

            let key = WordReplacementVariants.destinationKey(for: destination)
            if var group = groups[key] {
                group.sources = WordReplacementVariants.parse(
                    WordReplacementVariants.serialize(group.sources + sources)
                )
                group.createdAt = min(group.createdAt, item.dateAdded)
                groups[key] = group
            } else {
                groups[key] = ReplacementGroup(
                    sources: sources,
                    replacement: destination,
                    createdAt: item.dateAdded
                )
            }
        }

        let replacementEntries = groups.values
            .map {
                DictionaryReplacementEntry(
                    sources: $0.sources,
                    replacement: $0.replacement,
                    createdAt: $0.createdAt
                )
            }
            .sorted {
                let lhsKey = WordReplacementVariants.destinationKey(for: $0.replacement)
                let rhsKey = WordReplacementVariants.destinationKey(for: $1.replacement)
                if lhsKey != rhsKey { return lhsKey < rhsKey }
                return $0.sources.joined(separator: "\u{0}") < $1.sources.joined(separator: "\u{0}")
            }

        return DictionaryArchive(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            vocabulary: vocabularyEntries,
            replacements: replacementEntries
        )
    }

    private struct PreparedPlan: Sendable {
        let vocabulary: [DictionaryVocabularyEntry]
        let replacements: [DictionaryReplacementEntry]
        let summary: DictionaryImportSummary
    }

    private struct ReplacementCandidate: Sendable {
        let source: String
        let replacement: String
        let createdAt: Date?
    }

    private struct ExistingReplacement: Equatable, Sendable {
        let originalText: String
        let replacementText: String
    }

    private struct ExistingDictionarySnapshot: Equatable, Sendable {
        let vocabulary: [String]
        let replacements: [ExistingReplacement]
    }

    // MARK: - Planning

    @MainActor
    private static func makeSnapshot(modelContext: ModelContext) throws -> ExistingDictionarySnapshot {
        let vocabulary = try modelContext.fetch(FetchDescriptor<VocabularyWord>())
        let replacements = try modelContext.fetch(FetchDescriptor<WordReplacement>())
        return ExistingDictionarySnapshot(
            vocabulary: vocabulary.map(\.word).sorted(),
            replacements: replacements
                .map {
                    ExistingReplacement(
                        originalText: $0.originalText,
                        replacementText: $0.replacementText
                    )
                }
                .sorted {
                    if $0.originalText != $1.originalText {
                        return $0.originalText < $1.originalText
                    }
                    return $0.replacementText < $1.replacementText
                }
        )
    }

    private static func makePlan(
        archive: DictionaryArchive,
        mode: DictionaryImportMode,
        snapshot: ExistingDictionarySnapshot
    ) async throws -> PreparedPlan {
        let planningTask = Task.detached(priority: .userInitiated) {
            try buildPlan(archive: archive, mode: mode, snapshot: snapshot)
        }
        return try await withTaskCancellationHandler {
            try await planningTask.value
        } onCancel: {
            planningTask.cancel()
        }
    }

    private static func buildPlan(
        archive: DictionaryArchive,
        mode: DictionaryImportMode,
        snapshot: ExistingDictionarySnapshot
    ) throws -> PreparedPlan {
        guard archive.format == DictionaryArchive.formatIdentifier else {
            throw DictionaryArchiveError.unsupportedFormat(archive.format)
        }
        guard archive.schemaVersion == DictionaryArchive.currentSchemaVersion else {
            throw DictionaryArchiveError.unsupportedVersion(archive.schemaVersion)
        }

        let existingVocabulary = snapshot.vocabulary
        let existingReplacements = snapshot.replacements

        var invalidEntryCount = 0
        var commaContainingSourceCount = 0
        var duplicateVocabularyCount = 0
        var acceptedVocabulary: [DictionaryVocabularyEntry] = []
        var vocabularyKeys = mode == .merge
            ? Set(existingVocabulary.map { vocabularyKey($0) })
            : Set<String>()

        for (index, entry) in archive.vocabulary.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            let term = normalizedText(entry.term)
            guard !term.isEmpty else {
                invalidEntryCount += 1
                continue
            }

            let key = vocabularyKey(term)
            guard vocabularyKeys.insert(key).inserted else {
                duplicateVocabularyCount += 1
                continue
            }
            acceptedVocabulary.append(DictionaryVocabularyEntry(term: term, createdAt: entry.createdAt))
        }

        var candidates: [ReplacementCandidate] = []
        for (index, entry) in archive.replacements.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            let replacement = WordReplacementVariants.destinationKey(for: entry.replacement)
            let sources = entry.sources.map(normalizedText)
            guard !sources.contains(where: { $0.contains(",") }) else {
                commaContainingSourceCount += 1
                continue
            }
            guard !replacement.isEmpty, !sources.isEmpty, !sources.contains(where: \.isEmpty) else {
                invalidEntryCount += 1
                continue
            }

            candidates.append(
                contentsOf: sources.map {
                    ReplacementCandidate(
                        source: $0,
                        replacement: replacement,
                        createdAt: entry.createdAt
                    )
                }
            )
        }

        var existingDestinationsBySource: [String: Set<String>] = [:]
        if mode == .merge {
            for replacement in existingReplacements {
                let destinationKey = WordReplacementVariants.destinationKey(for: replacement.replacementText)
                for source in WordReplacementVariants.parse(replacement.originalText) {
                    existingDestinationsBySource[WordReplacementVariants.key(for: source), default: []]
                        .insert(destinationKey)
                }
            }
        }

        var duplicateReplacementCount = 0
        var conflictingReplacementCount = 0
        var cyclicReplacementCount = 0
        var importedDestinationBySource: [String: String] = [:]
        var acceptedCandidates: [ReplacementCandidate] = []
        let cycleRecords: [(originalText: String, replacementText: String)] = mode == .merge
            ? existingReplacements.map { ($0.originalText, $0.replacementText) }
            : []
        var cycleDetector = WordReplacementVariants.CycleDetector(records: cycleRecords)

        for (index, candidate) in candidates.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            let sourceKey = WordReplacementVariants.key(for: candidate.source)
            let destinationKey = WordReplacementVariants.destinationKey(for: candidate.replacement)

            if let importedDestination = importedDestinationBySource[sourceKey] {
                if importedDestination == destinationKey {
                    duplicateReplacementCount += 1
                } else {
                    conflictingReplacementCount += 1
                }
                continue
            }

            if let existingDestinations = existingDestinationsBySource[sourceKey] {
                if existingDestinations.count == 1, existingDestinations.contains(destinationKey) {
                    duplicateReplacementCount += 1
                } else {
                    conflictingReplacementCount += 1
                }
                continue
            }

            if !cycleDetector.insertIfAcyclic(
                source: candidate.source,
                destination: candidate.replacement
            ) {
                cyclicReplacementCount += 1
                continue
            }

            importedDestinationBySource[sourceKey] = destinationKey
            acceptedCandidates.append(candidate)
        }

        var groupOrder: [String] = []
        var groupedCandidates: [String: [ReplacementCandidate]] = [:]
        for candidate in acceptedCandidates {
            let key = WordReplacementVariants.destinationKey(for: candidate.replacement)
            if groupedCandidates[key] == nil {
                groupOrder.append(key)
            }
            groupedCandidates[key, default: []].append(candidate)
        }

        let acceptedReplacements = groupOrder.compactMap { key -> DictionaryReplacementEntry? in
            guard let group = groupedCandidates[key], let first = group.first else { return nil }
            let createdAt = group.compactMap(\.createdAt).min()
            return DictionaryReplacementEntry(
                sources: group.map(\.source),
                replacement: first.replacement,
                createdAt: createdAt
            )
        }

        let summary = DictionaryImportSummary(
            vocabularyToImport: acceptedVocabulary.count,
            replacementRulesToImport: acceptedReplacements.count,
            replacementSourcesToImport: acceptedCandidates.count,
            duplicateVocabularyCount: duplicateVocabularyCount,
            duplicateReplacementCount: duplicateReplacementCount,
            conflictingReplacementCount: conflictingReplacementCount,
            invalidEntryCount: invalidEntryCount,
            commaContainingSourceCount: commaContainingSourceCount,
            cyclicReplacementCount: cyclicReplacementCount,
            vocabularyToRemove: mode == .replace ? existingVocabulary.count : 0,
            replacementsToRemove: mode == .replace ? existingReplacements.count : 0
        )

        return PreparedPlan(
            vocabulary: acceptedVocabulary,
            replacements: acceptedReplacements,
            summary: summary
        )
    }

    private static func normalizedText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
    }

    private static func vocabularyKey(_ text: String) -> String {
        let normalized = normalizedText(text)
        return (normalized as NSString).folding(options: .caseInsensitive, locale: nil)
    }
}
