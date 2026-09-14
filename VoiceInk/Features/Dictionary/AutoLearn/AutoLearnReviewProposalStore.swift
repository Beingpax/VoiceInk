import Foundation

actor AutoLearnReviewProposalStore {
    private let fileManager: FileManager
    private let fileURL: URL
    private var proposals: [AutoLearnReviewProposal] = []
    private var isLoaded = false

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        fileURL = applicationSupport
            .appendingPathComponent("com.prakashjoshipax.VoiceInk", isDirectory: true)
            .appendingPathComponent("auto-learn-review-proposals.json")
    }

    func all() throws -> [AutoLearnReviewProposal] {
        try loadIfNeeded()
        return proposals
    }

    func append(
        decisions: [AutoLearnReviewDecision],
        candidates: [AutoLearnReviewCandidate]
    ) throws {
        try loadIfNeeded()
        let candidatesByID = Dictionary(
            uniqueKeysWithValues: candidates.map { ($0.candidateID, $0) }
        )
        let additions = decisions.compactMap { decision -> AutoLearnReviewProposal? in
            guard decision.learningAction != .rejectCorrection,
                let candidate = candidatesByID[decision.candidateID]
            else { return nil }

            return AutoLearnReviewProposal(
                id: UUID(),
                candidateID: decision.candidateID,
                originalText: candidate.originalText,
                correctedText: candidate.correctedText,
                learningAction: decision.learningAction,
                incorrectTextToReplace: decision.incorrectTextToReplace,
                correctedVocabularyTerm: decision.correctedVocabularyTerm
            )
        }
        var knownKeys = Set(proposals.map(Self.proposalKey))
        let uniqueAdditions = additions.filter {
            knownKeys.insert(Self.proposalKey($0)).inserted
        }
        guard !uniqueAdditions.isEmpty else { return }
        let originalProposals = proposals
        proposals.append(contentsOf: uniqueAdditions)
        do {
            try save()
        } catch {
            proposals = originalProposals
            throw error
        }
    }

    func remove(_ proposalIDs: Set<UUID>) throws {
        guard !proposalIDs.isEmpty else { return }
        try loadIfNeeded()
        let originalProposals = proposals
        let originalCount = proposals.count
        proposals.removeAll { proposalIDs.contains($0.id) }
        if proposals.count != originalCount {
            do {
                try save()
            } catch {
                proposals = originalProposals
                throw error
            }
        }
    }

    func update(
        proposalID: UUID,
        incorrectTextToReplace: String?,
        correctedVocabularyTerm: String
    ) throws {
        try loadIfNeeded()
        guard let index = proposals.firstIndex(where: { $0.id == proposalID }) else { return }

        let proposal = proposals[index]
        let updatedProposal = AutoLearnReviewProposal(
            id: proposal.id,
            candidateID: proposal.candidateID,
            originalText: proposal.originalText,
            correctedText: proposal.correctedText,
            learningAction: proposal.learningAction,
            incorrectTextToReplace: incorrectTextToReplace,
            correctedVocabularyTerm: correctedVocabularyTerm
        )
        guard Self.proposalKey(updatedProposal) != Self.proposalKey(proposal) else { return }

        let originalProposals = proposals
        proposals[index] = updatedProposal
        do {
            try save()
        } catch {
            proposals = originalProposals
            throw error
        }
    }

    private func loadIfNeeded() throws {
        guard !isLoaded else { return }
        defer { isLoaded = true }
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        let data = try Data(contentsOf: fileURL)
        proposals = try JSONDecoder().decode([AutoLearnReviewProposal].self, from: data)
    }

    private func save() throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(proposals).write(to: fileURL, options: .atomic)
    }

    private static func proposalKey(_ proposal: AutoLearnReviewProposal) -> String {
        [
            proposal.candidateID.uuidString,
            proposal.learningAction.rawValue,
            proposal.incorrectTextToReplace ?? "",
            proposal.correctedVocabularyTerm ?? ""
        ].joined(separator: "\u{0}")
    }
}
