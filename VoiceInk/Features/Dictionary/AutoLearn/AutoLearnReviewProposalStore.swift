import Foundation

actor AutoLearnReviewProposalStore {
    private struct ObservedOriginal: Codable, Equatable {
        var id: UUID
        var candidateID: UUID
        var text: String
        var suggestionOrder: Int?

        func decision(replacementText: String) -> AutoLearnReviewDecision {
            AutoLearnReviewDecision(candidateID: candidateID, learningAction: .addReplacementOnly,
                incorrectTextToReplace: text, correctedVocabularyTerm: replacementText)
        }
    }

    private struct CountedReplacement: Codable, Equatable {
        let replacementText: String
        var count: Int
        var originals: [ObservedOriginal]
    }

    private struct StoredState: Codable {
        let corrections: [CountedReplacement]
    }

    private struct DecodedState {
        let corrections: [CountedReplacement]
        var dismissedPairs: Set<String>? = nil
        var needsMigration = false
    }

    private struct LegacyCountedCorrection: Decodable {
        let count: Int
        let lastCandidateID: UUID
        let proposal: AutoLearnReviewProposal
    }

    private struct LegacyCountedState: Decodable {
        let proposals: [AutoLearnReviewProposal]
        let correctionCounts: [String: LegacyCountedCorrection]
        let destinationCounts: [String: Int]?
    }

    private struct LegacyProposalState: Decodable {
        let proposals: [AutoLearnReviewProposal]
        let dismissedPairs: [String]
    }

    private let fileManager: FileManager
    private let fileURL: URL
    private let dismissedPairsFileURL: URL
    private let legacyFileURLs: [(old: URL, new: URL)]
    private var corrections: [CountedReplacement] = []
    private var dismissedPairs = Set<String>()
    private var isLoaded = false

    init(fileManager: FileManager = .default, fileURL: URL? = nil, dismissedPairsFileURL: URL? = nil) {
        self.fileManager = fileManager
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let proposalsURL = fileURL ?? applicationSupport
            .appendingPathComponent("com.prakashjoshipax.VoiceInk", isDirectory: true)
            .appendingPathComponent("auto-learn-suggestions.json")
        self.fileURL = proposalsURL
        let dismissedURL = dismissedPairsFileURL ?? proposalsURL.deletingLastPathComponent()
            .appendingPathComponent("auto-learn-dismissed-corrections.json")
        self.dismissedPairsFileURL = dismissedURL
        var legacyFiles: [(old: URL, new: URL)] = []
        if fileURL == nil {
            legacyFiles.append((proposalsURL.deletingLastPathComponent()
                .appendingPathComponent("auto-learn-review-proposals.json"), proposalsURL))
        }
        if fileURL == nil, dismissedPairsFileURL == nil {
            legacyFiles.append((dismissedURL.deletingLastPathComponent()
                .appendingPathComponent("auto-learn-dismissed-pairs.json"), dismissedURL))
        }
        legacyFileURLs = legacyFiles
    }

    func all() throws -> [AutoLearnSuggestion] {
        try loadIfNeeded()
        let superseded = Self.supersededPairs(in: corrections)
        return corrections.compactMap { correction -> (order: Int, suggestion: AutoLearnSuggestion)? in
            let ready = correction.originals.filter {
                $0.suggestionOrder != nil && !superseded.contains(Self.correctionKey(
                    source: $0.text, destination: correction.replacementText))
            }
            guard let order = ready.compactMap(\.suggestionOrder).min() else { return nil }
            return (order, AutoLearnSuggestion(replacementText: correction.replacementText,
                originals: ready.map { .init(id: $0.id, text: $0.text) }))
        }.sorted {
            $0.order == $1.order ? $0.suggestion.id < $1.suggestion.id : $0.order < $1.order
        }.map { $0.suggestion }
    }

    func matching(_ suggestion: AutoLearnSuggestion) throws -> AutoLearnSuggestion? {
        guard let current = try all().first(where: { $0.id == suggestion.id }) else { return nil }
        let originals = current.originals.filter { suggestion.originals.contains($0) }
        guard !originals.isEmpty else { return nil }
        return AutoLearnSuggestion(replacementText: current.replacementText, originals: originals)
    }

    func countedSuggestions() throws -> [AutoLearnReviewDecision] {
        try loadIfNeeded()
        return corrections.flatMap { correction in
            correction.originals.map { $0.decision(replacementText: correction.replacementText) }
        }
    }

    func dataHealth() throws -> AutoLearnDataHealth {
        try AutoLearnDataRepair.health(of: dataFiles)
    }

    func repairDamagedData() throws {
        try AutoLearnDataRepair.repair(dataFiles) {
            corrections = []
            dismissedPairs = []
            isLoaded = false
        }
    }

    private var dataFiles: [AutoLearnDataRepair.File] {
        [(fileURL, false), (dismissedPairsFileURL, true)].map { url, resetsDismissals in
            let legacy = legacyFileURLs.first { $0.new == url }?.old
            let resolved = !fileManager.fileExists(atPath: url.path) ? legacy ?? url : url
            return AutoLearnDataRepair.File(url: resolved, resetsDismissals: resetsDismissals,
                initialData: {
                    resetsDismissals ? Data("[]".utf8) : try JSONEncoder().encode(StoredState(corrections: []))
                }, validate: { data in
                    if resetsDismissals {
                        _ = try JSONDecoder().decode([String].self, from: data)
                    } else {
                        _ = try Self.decodeState(from: data)
                    }
                })
        }
    }

    func discardAll() throws {
        try loadIfNeeded()
        guard !corrections.isEmpty || fileManager.fileExists(atPath: fileURL.path) else { return }
        let snapshot = corrections
        corrections = []
        try saveChanges(restoring: snapshot)
    }

    @discardableResult
    func update(
        decisions: [AutoLearnReviewDecision] = [],
        candidates: [AutoLearnReviewCandidate] = [],
        minimumCorrections: Int,
        eligibleDecisions: [AutoLearnReviewDecision]
    ) throws -> Int {
        try loadIfNeeded()
        let threshold = AutoLearnSettings.clampedMinimumCorrections(minimumCorrections)
        let candidatesByID = Dictionary(candidates.map { ($0.candidateID, $0) },
            uniquingKeysWith: { first, _ in first })
        let snapshot = corrections
        var updatedDismissedPairs = dismissedPairs
        let previousSuggestionIDs = suggestedReplacementIDs
        let eligiblePairs = Set(eligibleDecisions.map {
            Self.correctionKey(source: $0.incorrectTextToReplace, destination: $0.correctedVocabularyTerm)
        })

        for decision in decisions {
            guard decision.learningAction == .addReplacementOnly,
                let candidate = candidatesByID[decision.candidateID],
                let source = decision.incorrectTextToReplace,
                let destination = decision.correctedVocabularyTerm,
                AutoLearnLocalReviewPolicy.accepts(source: source, destination: destination),
                eligiblePairs.contains(Self.correctionKey(source: source, destination: destination)),
                !updatedDismissedPairs.contains(Self.correctionKey(source: source, destination: destination))
            else { continue }

            let replacementText = WordReplacementVariants.destinationKey(for: destination)
            let sourceKey = WordReplacementVariants.key(for: source)
            updatedDismissedPairs.formUnion(correctionPairs(for: [sourceKey], excluding: replacementText))
            let index: Int
            if let existing = corrections.firstIndex(where: { $0.replacementText == replacementText }) {
                index = existing
            } else {
                index = corrections.endIndex
                corrections.append(CountedReplacement(replacementText: replacementText, count: 0, originals: []))
            }
            var correction = corrections[index]
            if let existing = correction.originals.firstIndex(where: {
                WordReplacementVariants.key(for: $0.text) == sourceKey
            }) {
                if correction.originals[existing].candidateID != candidate.candidateID {
                    correction.originals[existing].candidateID = candidate.candidateID
                    correction.count = AutoLearnSettings.clampedMinimumCorrections(correction.count + 1)
                }
            } else {
                correction.originals.append(ObservedOriginal(id: UUID(), candidateID: candidate.candidateID,
                    text: source.trimmingCharacters(in: .whitespacesAndNewlines)
                        .precomposedStringWithCanonicalMapping,
                    suggestionOrder: nil))
                correction.count = AutoLearnSettings.clampedMinimumCorrections(correction.count + 1)
            }
            corrections[index] = correction
        }

        var order = nextSuggestionOrder
        for index in corrections.indices {
            var correction = corrections[index]
            let destination = correction.replacementText
            correction.originals.removeAll {
                let key = Self.correctionKey(source: $0.text, destination: destination)
                return !eligiblePairs.contains(key) || updatedDismissedPairs.contains(key)
            }
            for originalIndex in correction.originals.indices {
                if correction.count < threshold {
                    correction.originals[originalIndex].suggestionOrder = nil
                } else if correction.originals[originalIndex].suggestionOrder == nil {
                    correction.originals[originalIndex].suggestionOrder = order
                    order += 1
                }
            }
            corrections[index] = correction
        }
        guard corrections != snapshot else { return 0 }
        try saveChanges(restoring: snapshot, dismissedPairs: updatedDismissedPairs)
        return suggestedReplacementIDs.subtracting(previousSuggestionIDs).count
    }

    func removeApprovedSuggestion(_ suggestion: AutoLearnSuggestion) throws {
        let originalIDs = suggestion.originalIDs
        guard !originalIDs.isEmpty else { return }
        try loadIfNeeded()
        let snapshot = corrections
        let sources = Set(suggestion.originals.map { WordReplacementVariants.key(for: $0.text) })
        let updatedPairs = dismissedPairs.union(correctionPairs(for: sources, excluding: suggestion.replacementText))
        for index in corrections.indices {
            let destination = corrections[index].replacementText
            corrections[index].originals.removeAll {
                ($0.suggestionOrder != nil && originalIDs.contains($0.id))
                    || updatedPairs.contains(Self.correctionKey(source: $0.text, destination: destination))
            }
        }
        guard corrections != snapshot else { return }
        try saveChanges(restoring: snapshot, dismissedPairs: updatedPairs)
    }

    func dismiss(_ suggestion: AutoLearnSuggestion) throws {
        guard let dismissed = try matching(suggestion) else { return }
        let sources = Set(dismissed.originals.map { WordReplacementVariants.key(for: $0.text) })
        let updatedPairs = dismissedPairs.union(correctionPairs(for: sources))
        try write(updatedPairs.sorted(), to: dismissedPairsFileURL)
        dismissedPairs = updatedPairs
        for index in corrections.indices {
            let destination = corrections[index].replacementText
            corrections[index].originals.removeAll {
                updatedPairs.contains(Self.correctionKey(source: $0.text, destination: destination))
            }
        }
        try? save()
    }

    private func correctionPairs(for sources: Set<String>, excluding replacement: String? = nil) -> Set<String> {
        var pairs = Set<String>()
        for correction in corrections where correction.replacementText != replacement {
            for original in correction.originals where sources.contains(WordReplacementVariants.key(for: original.text)) {
                pairs.insert(Self.correctionKey(source: original.text, destination: correction.replacementText))
            }
        }
        return pairs
    }

    private func loadIfNeeded() throws {
        guard !isLoaded else { return }
        for (oldURL, newURL) in legacyFileURLs
        where !fileManager.fileExists(atPath: newURL.path)
            && fileManager.fileExists(atPath: oldURL.path) {
            try fileManager.moveItem(at: oldURL, to: newURL)
        }
        let decoder = JSONDecoder()
        var loadedDismissedPairs = Set<String>()
        if fileManager.fileExists(atPath: dismissedPairsFileURL.path) {
            let data = try Data(contentsOf: dismissedPairsFileURL)
            loadedDismissedPairs = Set(try decoder.decode([String].self, from: data))
        }

        var loadedCorrections: [CountedReplacement] = []
        var needsMigration = false
        if fileManager.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            let state = try Self.decodeState(from: data)
            loadedCorrections = state.corrections
            needsMigration = state.needsMigration
            if let legacyDismissedPairs = state.dismissedPairs {
                loadedDismissedPairs.formUnion(legacyDismissedPairs)
                try write(loadedDismissedPairs.sorted(), to: dismissedPairsFileURL)
            }
        }
        loadedCorrections = Self.validated(loadedCorrections, dismissedPairs: loadedDismissedPairs)
        if needsMigration {
            try write(StoredState(corrections: loadedCorrections), to: fileURL)
        }
        corrections = loadedCorrections
        dismissedPairs = loadedDismissedPairs
        isLoaded = true
    }

    private static func decodeState(from data: Data) throws -> DecodedState {
        let decoder = JSONDecoder()
        if let state = try? decoder.decode(StoredState.self, from: data) {
            return DecodedState(corrections: state.corrections)
        }
        if let legacy = try? decoder.decode(LegacyCountedState.self, from: data) {
            return DecodedState(corrections: migrate(proposals: legacy.proposals,
                counts: legacy.correctionCounts, destinationCounts: legacy.destinationCounts), needsMigration: true)
        }
        if let legacy = try? decoder.decode(LegacyProposalState.self, from: data) {
            return DecodedState(corrections: migrate(proposals: legacy.proposals),
                dismissedPairs: Set(legacy.dismissedPairs), needsMigration: true)
        }
        let proposals = try decoder.decode([AutoLearnReviewProposal].self, from: data)
        return DecodedState(corrections: migrate(proposals: proposals), needsMigration: true)
    }

    private static func migrate(proposals: [AutoLearnReviewProposal],
        counts: [String: LegacyCountedCorrection] = [:],
        destinationCounts: [String: Int]? = nil) -> [CountedReplacement] {
        var groups: [String: CountedReplacement] = [:]
        for (key, observation) in counts.sorted(by: { $0.key < $1.key }) {
            let proposal = observation.proposal
            guard valid(proposal), key == correctionKey(proposal), observation.count > 0,
                observation.lastCandidateID == proposal.candidateID,
                let source = proposal.incorrectTextToReplace,
                let destination = proposal.correctedVocabularyTerm else { continue }
            let replacement = WordReplacementVariants.destinationKey(for: destination)
            var group = groups[replacement] ?? CountedReplacement(replacementText: replacement, count: 0, originals: [])
            group.count = AutoLearnSettings.clampedMinimumCorrections(
                group.count + AutoLearnSettings.clampedMinimumCorrections(observation.count))
            group.originals.append(ObservedOriginal(id: proposal.id, candidateID: observation.lastCandidateID,
                text: source, suggestionOrder: nil))
            groups[replacement] = group
        }
        for (order, proposal) in proposals.enumerated() {
            guard valid(proposal), let source = proposal.incorrectTextToReplace,
                let destination = proposal.correctedVocabularyTerm else { continue }
            let replacement = WordReplacementVariants.destinationKey(for: destination)
            var group = groups[replacement] ?? CountedReplacement(replacementText: replacement, count: 0, originals: [])
            if let index = group.originals.firstIndex(where: {
                WordReplacementVariants.key(for: $0.text) == WordReplacementVariants.key(for: source)
            }) {
                group.originals[index].id = proposal.id
                group.originals[index].suggestionOrder = order
            } else {
                group.originals.append(ObservedOriginal(id: proposal.id, candidateID: proposal.candidateID,
                    text: source, suggestionOrder: order))
                group.count = 3
            }
            groups[replacement] = group
        }
        for (replacement, count) in destinationCounts ?? [:] {
            guard count > 0, replacement == WordReplacementVariants.destinationKey(for: replacement),
                AutoLearnLocalReviewPolicy.accepts(source: nil, destination: replacement) else { continue }
            var group = groups[replacement] ?? CountedReplacement(replacementText: replacement, count: 0, originals: [])
            group.count = AutoLearnSettings.clampedMinimumCorrections(count)
            groups[replacement] = group
        }
        return groups.keys.sorted().compactMap { groups[$0] }
    }

    private static func validated(_ loaded: [CountedReplacement],
        dismissedPairs: Set<String>) -> [CountedReplacement] {
        var groups: [CountedReplacement] = []
        var knownIDs = Set<UUID>()
        for correction in loaded {
            let replacement = WordReplacementVariants.destinationKey(for: correction.replacementText)
            guard correction.count > 0,
                AutoLearnLocalReviewPolicy.accepts(source: nil, destination: replacement) else { continue }
            let index: Int
            if let existing = groups.firstIndex(where: { $0.replacementText == replacement }) {
                index = existing
            } else {
                index = groups.endIndex
                groups.append(CountedReplacement(replacementText: replacement, count: 0, originals: []))
            }
            var group = groups[index]
            group.count = max(group.count, AutoLearnSettings.clampedMinimumCorrections(correction.count))
            var sources = Set(group.originals.map { WordReplacementVariants.key(for: $0.text) })
            for var original in correction.originals {
                original.text = original.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    .precomposedStringWithCanonicalMapping
                guard AutoLearnLocalReviewPolicy.accepts(source: original.text, destination: replacement),
                    !dismissedPairs.contains(correctionKey(source: original.text, destination: replacement)),
                    !knownIDs.contains(original.id),
                    sources.insert(WordReplacementVariants.key(for: original.text)).inserted else { continue }
                knownIDs.insert(original.id)
                if let order = original.suggestionOrder, order < 0 { original.suggestionOrder = nil }
                group.originals.append(original)
            }
            groups[index] = group
        }
        let suggested = groups.flatMap(\.originals).compactMap { original -> (id: UUID, order: Int)? in
            original.suggestionOrder.map { (original.id, $0) }
        }.sorted {
            $0.order == $1.order ? $0.id.uuidString < $1.id.uuidString : $0.order < $1.order
        }
        let orderByID = Dictionary(uniqueKeysWithValues: suggested.enumerated().map { ($0.element.id, $0.offset) })
        for index in groups.indices {
            for originalIndex in groups[index].originals.indices {
                let id = groups[index].originals[originalIndex].id
                groups[index].originals[originalIndex].suggestionOrder = orderByID[id]
            }
        }
        return groups
    }

    private static func valid(_ proposal: AutoLearnReviewProposal) -> Bool {
        guard proposal.learningAction == .addReplacementOnly,
            let source = proposal.incorrectTextToReplace,
            let destination = proposal.correctedVocabularyTerm else { return false }
        return AutoLearnLocalReviewPolicy.accepts(source: source, destination: destination)
    }

    private static func supersededPairs(in corrections: [CountedReplacement]) -> Set<String> {
        var latest: [String: (destination: String, order: Int)] = [:]
        var superseded = Set<String>()
        for correction in corrections {
            for original in correction.originals {
                let sourceKey = WordReplacementVariants.key(for: original.text)
                let order = original.suggestionOrder ?? -1
                if let previous = latest[sourceKey], previous.destination != correction.replacementText {
                    if order < previous.order {
                        superseded.insert(correctionKey(source: original.text, destination: correction.replacementText))
                        continue
                    }
                    superseded.insert(correctionKey(source: original.text, destination: previous.destination))
                }
                latest[sourceKey] = (correction.replacementText, order)
            }
        }
        return superseded
    }

    private var suggestedReplacementIDs: Set<String> {
        Set(corrections.filter { $0.originals.contains { $0.suggestionOrder != nil } }.map(\.replacementText))
    }

    private var nextSuggestionOrder: Int {
        (corrections.flatMap(\.originals).compactMap(\.suggestionOrder).max() ?? -1) + 1
    }

    private func saveChanges(restoring snapshot: [CountedReplacement], dismissedPairs updatedPairs: Set<String>? = nil) throws {
        let previousDismissedPairs = dismissedPairs
        var wroteDismissals = false
        do {
            if let updatedPairs, updatedPairs != dismissedPairs {
                try write(updatedPairs.sorted(), to: dismissedPairsFileURL)
                wroteDismissals = true
            }
            try save()
            if let updatedPairs { dismissedPairs = updatedPairs }
        } catch {
            corrections = snapshot
            if wroteDismissals {
                try write(previousDismissedPairs.sorted(), to: dismissedPairsFileURL)
            }
            throw error
        }
    }

    private func save() throws {
        try write(StoredState(corrections: corrections), to: fileURL)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private static func correctionKey(_ proposal: AutoLearnReviewProposal) -> String {
        correctionKey(source: proposal.incorrectTextToReplace, destination: proposal.correctedVocabularyTerm)
    }

    private static func correctionKey(source: String?, destination: String?) -> String {
        [
            WordReplacementVariants.key(for: source ?? ""),
            WordReplacementVariants.destinationKey(for: destination ?? "")
        ].joined(separator: "\u{0}")
    }
}
