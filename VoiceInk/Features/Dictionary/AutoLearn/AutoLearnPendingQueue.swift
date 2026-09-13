import Foundation

actor AutoLearnPendingQueue {
    private enum ReviewStatus: String, Codable {
        case pending
        case reviewing
    }

    private struct QueuedCorrection: Codable {
        let candidateID: UUID
        let originalText: String
        let correctedText: String
        var reviewStatus: ReviewStatus

        var reviewCandidate: AutoLearnReviewCandidate {
            AutoLearnReviewCandidate(
                candidateID: candidateID,
                originalText: originalText,
                correctedText: correctedText
            )
        }

        private enum CodingKeys: String, CodingKey {
            case candidateID
            case originalText
            case correctedText
            case reviewStatus
            case detectedOriginalText
            case userCorrectedText
            case originalTextContext
            case correctedTextContext
        }

        init(
            candidateID: UUID,
            originalText: String,
            correctedText: String,
            reviewStatus: ReviewStatus
        ) {
            self.candidateID = candidateID
            self.originalText = originalText
            self.correctedText = correctedText
            self.reviewStatus = reviewStatus
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            candidateID = try container.decode(UUID.self, forKey: .candidateID)
            reviewStatus = try container.decode(ReviewStatus.self, forKey: .reviewStatus)

            if let value = try container.decodeIfPresent(String.self, forKey: .originalText) {
                originalText = value
            } else if let legacyContext = try container.decodeIfPresent(
                String.self,
                forKey: .originalTextContext
            ) {
                originalText = legacyContext
            } else {
                originalText = try container.decode(String.self, forKey: .detectedOriginalText)
            }

            if let value = try container.decodeIfPresent(String.self, forKey: .correctedText) {
                correctedText = value
            } else if let legacyContext = try container.decodeIfPresent(
                String.self,
                forKey: .correctedTextContext
            ) {
                correctedText = legacyContext
            } else {
                correctedText = try container.decode(String.self, forKey: .userCorrectedText)
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(candidateID, forKey: .candidateID)
            try container.encode(originalText, forKey: .originalText)
            try container.encode(correctedText, forKey: .correctedText)
            try container.encode(reviewStatus, forKey: .reviewStatus)
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
                    originalText: $0.originalText,
                    correctedText: $0.correctedText
                )
            }
        )
        var insertedCount = 0
        for candidate in candidates {
            let originalText = candidate.originalText.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let correctedText = candidate.correctedText.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !originalText.isEmpty, !correctedText.isEmpty else { continue }

            let correctionPairKey = pairKey(
                originalText: originalText,
                correctedText: correctedText
            )
            guard knownPairs.insert(correctionPairKey).inserted else { continue }
            queuedCorrections.append(
                QueuedCorrection(
                    candidateID: UUID(),
                    originalText: originalText,
                    correctedText: correctedText,
                    reviewStatus: .pending
                )
            )
            insertedCount += 1
        }

        if insertedCount > 0 {
            do {
                try save()
            } catch {
                queuedCorrections = originalQueuedCorrections
                throw error
            }
        }
        return insertedCount
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
        originalText: String,
        correctedText: String
    ) -> String {
        WordReplacementVariants.key(for: originalText) + "\u{0}"
            + WordReplacementVariants.destinationKey(for: correctedText)
    }
}
