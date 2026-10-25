import Foundation
import OSLog

actor AutoLearnPendingQueue {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "AutoLearnQueue")
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

    init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        self.fileManager = fileManager
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        queueFileURL = fileURL ?? applicationSupport
            .appendingPathComponent("com.prakashjoshipax.VoiceInk", isDirectory: true)
            .appendingPathComponent("auto-learn-pending-corrections.json")
    }

    func discardAll() throws {
        try loadIfNeeded()
        guard !queuedCorrections.isEmpty || fileManager.fileExists(atPath: queueFileURL.path) else { return }
        let snapshot = queuedCorrections
        queuedCorrections = []
        do {
            try save()
        } catch {
            queuedCorrections = snapshot
            throw error
        }
    }

    func recoverInterruptedReviews() throws {
        try loadIfNeeded()
        let snapshot = queuedCorrections
        var changed = false
        for index in queuedCorrections.indices
        where queuedCorrections[index].reviewStatus == .reviewing {
            queuedCorrections[index].reviewStatus = .pending
            changed = true
        }
        if changed {
            do { try save() } catch { queuedCorrections = snapshot; throw error }
        }
        logger.notice("Auto Learn queue loaded outstanding=\(self.queuedCorrections.count, privacy: .public) interruptedReviewsRecovered=\(snapshot.filter { $0.reviewStatus == .reviewing }.count, privacy: .public)")
    }

    func enqueue(_ candidates: [DetectedCorrectionCandidate]) throws -> Int {
        guard !candidates.isEmpty else { return 0 }
        try loadIfNeeded()
        let originalQueuedCorrections = queuedCorrections

        var knownPairs = Set<String>()
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
            for correction in queuedCorrections.suffix(insertedCount) {
                logger.notice("Auto Learn candidate saved candidateID=\(correction.candidateID.uuidString, privacy: .public) status=pending originalCharacters=\(correction.originalText.count, privacy: .public) correctedCharacters=\(correction.correctedText.count, privacy: .public)")
            }
        }
        return insertedCount
    }

    func pendingCount() throws -> Int {
        try loadIfNeeded()
        return queuedCorrections.filter { $0.reviewStatus == .pending }.count
    }

    func dataHealth() throws -> AutoLearnDataHealth {
        try AutoLearnDataRepair.health(of: [dataFile])
    }

    func repairDamagedData() throws {
        try AutoLearnDataRepair.repair([dataFile]) {
            queuedCorrections = []
            queuedCorrectionsWereLoaded = false
        }
    }

    private var dataFile: AutoLearnDataRepair.File {
        .init(url: queueFileURL, initialData: { Data("[]".utf8) }, validate: {
            _ = try Self.decodeCorrections(from: $0)
        })
    }

    func claimNext() throws -> AutoLearnReviewCandidate? {
        try loadIfNeeded()
        guard let index = queuedCorrections.firstIndex(where: { $0.reviewStatus == .pending }) else {
            return nil
        }

        queuedCorrections[index].reviewStatus = .reviewing
        do {
            try save()
        } catch {
            queuedCorrections[index].reviewStatus = .pending
            throw error
        }
        return queuedCorrections[index].reviewCandidate
    }

    func release(_ candidateIDs: Set<UUID>) throws {
        guard !candidateIDs.isEmpty else { return }
        try loadIfNeeded()
        let snapshot = queuedCorrections

        var changed = false
        for index in queuedCorrections.indices
        where candidateIDs.contains(queuedCorrections[index].candidateID)
            && queuedCorrections[index].reviewStatus == .reviewing {
            queuedCorrections[index].reviewStatus = .pending
            changed = true
        }
        if changed {
            do { try save() } catch { queuedCorrections = snapshot; throw error }
        }
    }

    func remove(_ candidateIDs: Set<UUID>) throws {
        guard !candidateIDs.isEmpty else { return }
        try loadIfNeeded()

        let snapshot = queuedCorrections
        let originalCount = queuedCorrections.count
        queuedCorrections.removeAll { candidateIDs.contains($0.candidateID) }
        if queuedCorrections.count != originalCount {
            do { try save() } catch { queuedCorrections = snapshot; throw error }
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
            guard let record = record as? [String: Any],
                let recordData = try? JSONSerialization.data(withJSONObject: record) else {
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
