import Foundation

actor AutoLearnPendingQueue {
    private enum ReviewStatus: String, Codable {
        case pending
        case reviewing
    }

    private struct QueuedCorrection: Codable {
        let candidateID: UUID
        let detectedOriginalText: String
        let userCorrectedText: String
        let originalTextContext: String
        let correctedTextContext: String
        var reviewStatus: ReviewStatus

        var reviewCandidate: AutoLearnReviewCandidate {
            AutoLearnReviewCandidate(
                candidateID: candidateID,
                detectedOriginalText: detectedOriginalText,
                userCorrectedText: userCorrectedText,
                originalTextContext: originalTextContext,
                correctedTextContext: correctedTextContext
            )
        }
    }

    private let fileManager: FileManager
    private let queueFileURL: URL
    private var queuedCorrections: [QueuedCorrection] = []
    private var queuedCorrectionsWereLoaded = false

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        queueFileURL = applicationSupport
            .appendingPathComponent("com.prakashjoshipax.VoiceInk", isDirectory: true)
            .appendingPathComponent("auto-learn-pending-corrections.json")
    }

    func recoverInterruptedReviews() throws {
        try loadIfNeeded()
        var changed = false
        for index in queuedCorrections.indices
        where queuedCorrections[index].reviewStatus == .reviewing {
            queuedCorrections[index].reviewStatus = .pending
            changed = true
        }
        if changed {
            try save()
        }
    }

    func enqueue(_ candidates: [DetectedCorrectionCandidate]) throws -> Int {
        guard !candidates.isEmpty else { return 0 }
        try loadIfNeeded()
        let originalQueuedCorrections = queuedCorrections

        var knownPairs = Set(
            queuedCorrections.map {
                pairKey(
                    detectedOriginalText: $0.detectedOriginalText,
                    userCorrectedText: $0.userCorrectedText
                )
            }
        )
        var insertedCount = 0
        for candidate in candidates {
            let detectedOriginalText = candidate.detectedOriginalText.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let userCorrectedText = candidate.userCorrectedText.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !detectedOriginalText.isEmpty, !userCorrectedText.isEmpty else { continue }

            let correctionPairKey = pairKey(
                detectedOriginalText: detectedOriginalText,
                userCorrectedText: userCorrectedText
            )
            guard knownPairs.insert(correctionPairKey).inserted else { continue }
            queuedCorrections.append(
                QueuedCorrection(
                    candidateID: UUID(),
                    detectedOriginalText: detectedOriginalText,
                    userCorrectedText: userCorrectedText,
                    originalTextContext: candidate.originalTextContext,
                    correctedTextContext: candidate.correctedTextContext,
                    reviewStatus: .pending
                )
            )
            insertedCount += 1
        }

        if insertedCount > 0 {
            trimToLimit()
            do {
                try save()
            } catch {
                queuedCorrections = originalQueuedCorrections
                throw error
            }
        }
        return insertedCount
    }

    /// Bounds the persisted queue by dropping the oldest pending entries while
    /// preserving any batch currently under review.
    private func trimToLimit() {
        let overflow = queuedCorrections.count - AutoLearnLimits.maximumQueuedCorrections
        guard overflow > 0 else { return }

        var remainingToRemove = overflow
        queuedCorrections.removeAll { correction in
            guard remainingToRemove > 0, correction.reviewStatus == .pending else { return false }
            remainingToRemove -= 1
            return true
        }
    }

    /// Corrections that still need a review decision. Entries claimed by an
    /// in-flight batch are excluded so callers only see actionable work.
    func pendingCount() throws -> Int {
        try loadIfNeeded()
        return queuedCorrections.filter { $0.reviewStatus == .pending }.count
    }

    /// Every retained correction, including one currently under review. Used for
    /// status reporting so a claimed batch still counts as outstanding work.
    func outstandingCount() throws -> Int {
        try loadIfNeeded()
        return queuedCorrections.count
    }

    func claimPending(limit: Int) throws -> [AutoLearnReviewCandidate] {
        try loadIfNeeded()

        let pendingCorrectionIndices = queuedCorrections.indices
            .filter { queuedCorrections[$0].reviewStatus == .pending }
            .prefix(max(0, limit))
        guard !pendingCorrectionIndices.isEmpty else { return [] }

        for index in pendingCorrectionIndices {
            queuedCorrections[index].reviewStatus = .reviewing
        }
        do {
            try save()
        } catch {
            for index in pendingCorrectionIndices {
                queuedCorrections[index].reviewStatus = .pending
            }
            throw error
        }
        return pendingCorrectionIndices.map { queuedCorrections[$0].reviewCandidate }
    }

    func release(_ candidateIDs: Set<UUID>) throws {
        guard !candidateIDs.isEmpty else { return }
        try loadIfNeeded()

        var changed = false
        for index in queuedCorrections.indices
        where candidateIDs.contains(queuedCorrections[index].candidateID) {
            queuedCorrections[index].reviewStatus = .pending
            changed = true
        }
        if changed {
            try save()
        }
    }

    func remove(_ candidateIDs: Set<UUID>) throws {
        guard !candidateIDs.isEmpty else { return }
        try loadIfNeeded()

        let originalCount = queuedCorrections.count
        queuedCorrections.removeAll { candidateIDs.contains($0.candidateID) }
        if queuedCorrections.count != originalCount {
            try save()
        }
    }

    private func loadIfNeeded() throws {
        guard !queuedCorrectionsWereLoaded else { return }
        guard fileManager.fileExists(atPath: queueFileURL.path) else {
            queuedCorrectionsWereLoaded = true
            return
        }

        let data = try Data(contentsOf: queueFileURL)
        queuedCorrections = try Self.decodeCorrections(from: data)
        queuedCorrectionsWereLoaded = true
    }

    /// Decodes entry by entry so one unreadable record cannot strand the whole
    /// queue for the lifetime of the install.
    private static func decodeCorrections(from data: Data) throws -> [QueuedCorrection] {
        let decoder = JSONDecoder()
        guard let records = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Auto Learn queue file is not a JSON array"
                )
            )
        }

        return records.compactMap { record in
            guard let recordData = try? JSONSerialization.data(withJSONObject: record) else {
                return nil
            }
            return try? decoder.decode(QueuedCorrection.self, from: recordData)
        }
    }

    private func save() throws {
        let directory = queueFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(queuedCorrections)
        try data.write(to: queueFileURL, options: .atomic)
    }

    private func pairKey(
        detectedOriginalText: String,
        userCorrectedText: String
    ) -> String {
        WordReplacementVariants.key(for: detectedOriginalText) + "\u{0}"
            + WordReplacementVariants.destinationKey(for: userCorrectedText)
    }
}
