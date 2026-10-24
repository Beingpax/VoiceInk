import Foundation

actor AutoLearnReviewProposalStore {
    private struct CountedCorrection: Codable {
        var count: Int
        var lastCandidateID: UUID
        var proposal: AutoLearnReviewProposal
    }

    private struct StoredState: Codable {
        let proposals: [AutoLearnReviewProposal]
        let correctionCounts: [String: CountedCorrection]
    }

    private struct LegacyStoredState: Decodable {
        let proposals: [AutoLearnReviewProposal]
        let dismissedPairs: [String]
    }

    private let fileManager: FileManager
    private let fileURL: URL
    private let dismissedPairsFileURL: URL
    private var proposals: [AutoLearnReviewProposal] = []
    private var correctionCounts: [String: CountedCorrection] = [:]
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
            .appendingPathComponent("auto-learn-review-proposals.json")
        self.fileURL = proposalsURL
        self.dismissedPairsFileURL = dismissedPairsFileURL ?? proposalsURL.deletingLastPathComponent()
            .appendingPathComponent("auto-learn-dismissed-pairs.json")
    }

    func all() throws -> [AutoLearnReviewProposal] {
        try loadIfNeeded()
        return proposals
    }

    func countedSuggestions() throws -> [AutoLearnReviewDecision] {
        try loadIfNeeded()
        return correctionCounts.values.map { $0.proposal.reviewDecision }
    }

    func discardAll() throws {
        try loadIfNeeded()
        guard !proposals.isEmpty || !correctionCounts.isEmpty
            || fileManager.fileExists(atPath: fileURL.path) else { return }
        let snapshot = storedState
        proposals = []
        correctionCounts = [:]
        do {
            try save()
        } catch {
            restore(snapshot)
            throw error
        }
    }

    func append(
        decisions: [AutoLearnReviewDecision],
        candidates: [AutoLearnReviewCandidate],
        minimumCorrections: Int
    ) throws -> Int {
        try loadIfNeeded()
        let threshold = AutoLearnSettings.clampedMinimumCorrections(minimumCorrections)
        let candidatesByID = Dictionary(candidates.map { ($0.candidateID, $0) },
            uniquingKeysWith: { first, _ in first })
        let snapshot = storedState
        var knownPairs = Set(proposals.map(Self.correctionKey))
        var addedCount = 0
        var changed = false

        for decision in decisions {
            guard decision.learningAction == .addReplacementOnly,
                let candidate = candidatesByID[decision.candidateID],
                let source = decision.incorrectTextToReplace,
                let destination = decision.correctedVocabularyTerm,
                AutoLearnLocalReviewPolicy.accepts(source: source, destination: destination)
            else { continue }

            let key = Self.correctionKey(source: source, destination: destination)
            guard !dismissedPairs.contains(key) else { continue }
            var observation: CountedCorrection
            if let existing = correctionCounts[key] {
                observation = existing
                if observation.lastCandidateID != candidate.candidateID {
                    observation.count = AutoLearnSettings.clampedMinimumCorrections(observation.count + 1)
                    observation.lastCandidateID = candidate.candidateID
                    observation.proposal = Self.proposal(for: decision, candidate: candidate)
                    changed = true
                }
            } else {
                observation = CountedCorrection(count: 1, lastCandidateID: candidate.candidateID,
                    proposal: Self.proposal(for: decision, candidate: candidate))
                changed = true
            }
            correctionCounts[key] = observation
            if observation.count >= threshold, !knownPairs.contains(key) {
                proposals.append(observation.proposal)
                knownPairs.insert(key)
                addedCount += 1
                changed = true
            }
        }

        if changed {
            do {
                try save()
            } catch {
                restore(snapshot)
                throw error
            }
        }
        return addedCount
    }

    func updateThreshold(minimumCorrections: Int, eligibleDecisions: [AutoLearnReviewDecision]) throws {
        try loadIfNeeded()
        let threshold = AutoLearnSettings.clampedMinimumCorrections(minimumCorrections)
        let eligiblePairs = Set(eligibleDecisions.map {
            Self.correctionKey(source: $0.incorrectTextToReplace, destination: $0.correctedVocabularyTerm)
        })
        let snapshot = storedState
        correctionCounts = correctionCounts.filter {
            eligiblePairs.contains($0.key) && !dismissedPairs.contains($0.key)
        }
        proposals.removeAll {
            let key = Self.correctionKey($0)
            return !eligiblePairs.contains(key) || (correctionCounts[key]?.count ?? 0) < threshold
        }
        var knownPairs = Set(proposals.map(Self.correctionKey))
        for (key, observation) in correctionCounts.sorted(by: { $0.key < $1.key })
        where observation.count >= threshold && knownPairs.insert(key).inserted {
            proposals.append(observation.proposal)
        }
        guard proposals.map(\.id) != snapshot.proposals.map(\.id)
            || Set(correctionCounts.keys) != Set(snapshot.correctionCounts.keys) else { return }
        do {
            try save()
        } catch {
            restore(snapshot)
            throw error
        }
    }

    func remove(_ proposalIDs: Set<UUID>) throws {
        guard !proposalIDs.isEmpty else { return }
        try loadIfNeeded()
        let removed = proposals.filter { proposalIDs.contains($0.id) }
        guard !removed.isEmpty else { return }
        let snapshot = storedState
        for proposal in removed {
            correctionCounts[Self.correctionKey(proposal)] = nil
        }
        proposals.removeAll { proposalIDs.contains($0.id) }
        do {
            try save()
        } catch {
            restore(snapshot)
            throw error
        }
    }

    /// Explicit dismissal and an ignored popup both suppress this correction
    /// pair permanently. Approval removes a proposal without suppressing it.
    func dismiss(_ proposalIDs: Set<UUID>) throws {
        guard !proposalIDs.isEmpty else { return }
        try loadIfNeeded()
        let dismissed = proposals.filter { proposalIDs.contains($0.id) }
        guard !dismissed.isEmpty else { return }

        let updatedPairs = dismissedPairs.union(dismissed.map(Self.correctionKey))
        try write(updatedPairs.sorted(), to: dismissedPairsFileURL)
        dismissedPairs = updatedPairs
        proposals.removeAll { dismissedPairs.contains(Self.correctionKey($0)) }
        correctionCounts = correctionCounts.filter { !dismissedPairs.contains($0.key) }
        // History is authoritative and already saved. If proposal cleanup fails,
        // loading still filters these pairs, and the next save cleans up the file.
        try? save()
    }

    private func loadIfNeeded() throws {
        guard !isLoaded else { return }
        let decoder = JSONDecoder()
        var loadedDismissedPairs = Set<String>()
        if fileManager.fileExists(atPath: dismissedPairsFileURL.path) {
            let data = try Data(contentsOf: dismissedPairsFileURL)
            loadedDismissedPairs = Set(try decoder.decode([String].self, from: data))
        }

        var loadedProposals: [AutoLearnReviewProposal] = []
        var loadedCounts: [String: CountedCorrection] = [:]
        if fileManager.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            if let state = try? decoder.decode(StoredState.self, from: data) {
                loadedProposals = state.proposals
                loadedCounts = state.correctionCounts
            } else if let legacy = try? decoder.decode(LegacyStoredState.self, from: data) {
                loadedDismissedPairs.formUnion(legacy.dismissedPairs)
                loadedProposals = legacy.proposals.filter { !loadedDismissedPairs.contains(Self.correctionKey($0)) }
                // Save history first so interrupted migration cannot lose it.
                try write(loadedDismissedPairs.sorted(), to: dismissedPairsFileURL)
                try write(StoredState(proposals: loadedProposals, correctionCounts: [:]), to: fileURL)
            } else {
                loadedProposals = try decoder.decode([AutoLearnReviewProposal].self, from: data)
            }
        }
        dismissedPairs = loadedDismissedPairs
        proposals = loadedProposals.filter { !dismissedPairs.contains(Self.correctionKey($0)) }
        correctionCounts = loadedCounts.filter { key, observation in
            let proposal = observation.proposal
            guard !dismissedPairs.contains(key), key == Self.correctionKey(proposal),
                observation.count > 0, observation.lastCandidateID == proposal.candidateID,
                proposal.learningAction == .addReplacementOnly,
                let source = proposal.incorrectTextToReplace,
                let destination = proposal.correctedVocabularyTerm else { return false }
            return AutoLearnLocalReviewPolicy.accepts(source: source, destination: destination)
        }.mapValues {
            var observation = $0
            observation.count = AutoLearnSettings.clampedMinimumCorrections(observation.count)
            return observation
        }
        isLoaded = true
    }

    private var storedState: StoredState {
        StoredState(proposals: proposals, correctionCounts: correctionCounts)
    }

    private func restore(_ state: StoredState) {
        proposals = state.proposals
        correctionCounts = state.correctionCounts
    }

    private func save() throws {
        try write(storedState, to: fileURL)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private static func proposal(for decision: AutoLearnReviewDecision,
        candidate: AutoLearnReviewCandidate) -> AutoLearnReviewProposal {
        AutoLearnReviewProposal(id: UUID(), candidateID: candidate.candidateID,
            originalText: candidate.originalText, correctedText: candidate.correctedText,
            learningAction: decision.learningAction,
            incorrectTextToReplace: decision.incorrectTextToReplace,
            correctedVocabularyTerm: decision.correctedVocabularyTerm)
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
