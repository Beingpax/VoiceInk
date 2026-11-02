import Foundation
import OSLog

actor AutoLearnPendingQueue {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "AutoLearnQueue")
    private enum ReviewStatus: String, Codable {
        case pending
        case reviewing
        case incompatible
    }

    private struct QueuedCorrection: Codable {
        let candidateID: UUID
        let originalText: String
        let correctedText: String
        var observationID: UUID? = nil
        var reviewStatus: ReviewStatus

        var reviewCandidate: AutoLearnReviewCandidate {
            AutoLearnReviewCandidate(
                candidateID: candidateID,
                originalText: originalText,
                correctedText: correctedText,
                observationID: observationID
            )
        }

        private enum CodingKeys: String, CodingKey {
            case candidateID
            case originalText
            case correctedText
            case observationID
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
            reviewStatus: ReviewStatus,
            observationID: UUID? = nil
        ) {
            self.candidateID = candidateID
            self.originalText = originalText
            self.correctedText = correctedText
            self.reviewStatus = reviewStatus
            self.observationID = observationID
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            candidateID = try container.decode(UUID.self, forKey: .candidateID)
            observationID = try container.decodeIfPresent(UUID.self, forKey: .observationID)
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
            try container.encodeIfPresent(observationID, forKey: .observationID)
            try container.encode(reviewStatus, forKey: .reviewStatus)
        }
    }

    private struct ArchivedCorrection: Codable {
        let candidateID: UUID
        let originalText: String
        let correctedText: String
        var observationID: UUID? = nil
        var archivedAt: Date = Date()
    }

    // Keep the latest 500 archived corrections.
    private static let maximumArchivedCorrections = 500

    private let fileManager: FileManager
    private let queueFileURL: URL
    private let archiveFileURL: URL
    private var queuedCorrections: [QueuedCorrection] = []
    private var queuedCorrectionsWereLoaded = false

    init(fileManager: FileManager = .default, fileURL: URL? = nil, archiveFileURL: URL? = nil) {
        self.fileManager = fileManager
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let resolvedQueueURL = fileURL ?? applicationSupport
            .appendingPathComponent("com.prakashjoshipax.VoiceInk", isDirectory: true)
            .appendingPathComponent("auto-learn-pending-corrections.json")
        queueFileURL = resolvedQueueURL
        self.archiveFileURL = archiveFileURL ?? resolvedQueueURL.deletingLastPathComponent()
            .appendingPathComponent("auto-learn-incompatible-corrections.json")
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
        if archiveIncompatibleCorrections() { changed = true }
        if changed {
            do { try save() } catch { queuedCorrections = snapshot; throw error }
        }
        logger.notice("Auto Learn queue loaded outstanding=\(self.queuedCorrections.count, privacy: .public) interruptedReviewsRecovered=\(snapshot.filter { $0.reviewStatus == .reviewing }.count, privacy: .public)")
    }

    func enqueue(_ candidates: [DetectedCorrectionCandidate], observationID: UUID = UUID()) throws -> Int {
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
                    reviewStatus: .pending,
                    observationID: observationID
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

    func outstandingCount() throws -> Int {
        try loadIfNeeded()
        return queuedCorrections.filter { $0.reviewStatus != .incompatible }.count
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

    // Corrections arriving after this snapshot stay pending.
    func claimAllPending(usesAIReviewer: Bool = false) throws -> [AutoLearnReviewCandidate] {
        try loadIfNeeded()
        let snapshot = queuedCorrections

        var claimedCandidates: [AutoLearnReviewCandidate] = []
        var changed = false
        for index in queuedCorrections.indices where queuedCorrections[index].reviewStatus == .pending {
            changed = true
            let candidate = queuedCorrections[index].reviewCandidate
            if usesAIReviewer, !AutoLearnAIReviewer.canReview(candidate) {
                // Keep incompatible records out of review even if archiving fails.
                queuedCorrections[index].reviewStatus = .incompatible
            } else {
                queuedCorrections[index].reviewStatus = .reviewing
                claimedCandidates.append(candidate)
            }
        }
        if archiveIncompatibleCorrections() { changed = true }
        if changed {
            do { try save() } catch { queuedCorrections = snapshot; throw error }
        }
        return claimedCandidates
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
        let backup = queueFileURL.appendingPathExtension("pre-replacement-only.backup")
        if fileManager.fileExists(atPath: queueFileURL.path), !fileManager.fileExists(atPath: backup.path) {
            try fileManager.copyItem(at: queueFileURL, to: backup)
        }
        try data.write(to: queueFileURL, options: .atomic)
    }

    // Archive first; failed writes leave corrections parked in the queue.
    @discardableResult
    private func archiveIncompatibleCorrections() -> Bool {
        let incompatible = queuedCorrections.filter { $0.reviewStatus == .incompatible }
        guard !incompatible.isEmpty else { return false }
        do {
            try archive(incompatible)
            let archivedIDs = Set(incompatible.map(\.candidateID))
            queuedCorrections.removeAll { archivedIDs.contains($0.candidateID) }
            return true
        } catch {
            logger.error("Failed to archive incompatible Auto Learn candidates; retained in queue: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func archive(_ discarded: [QueuedCorrection]) throws {
        var archived: [ArchivedCorrection] = []
        if fileManager.fileExists(atPath: archiveFileURL.path) {
            let data = try Data(contentsOf: archiveFileURL)
            archived = try Self.decodeArchive(from: data)
        }
        // Queue-save failures can replay an already archived correction.
        var knownIDs = Set(archived.map(\.candidateID))
        for correction in discarded where knownIDs.insert(correction.candidateID).inserted {
            archived.append(ArchivedCorrection(candidateID: correction.candidateID,
                originalText: correction.originalText, correctedText: correction.correctedText,
                observationID: correction.observationID))
        }
        if archived.count > Self.maximumArchivedCorrections {
            archived.removeFirst(archived.count - Self.maximumArchivedCorrections)
        }

        let directory = archiveFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(archived)
        try data.write(to: archiveFileURL, options: .atomic)
    }

    private static func decodeArchive(from data: Data) throws -> [ArchivedCorrection] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ArchivedCorrection].self, from: data)
    }

    private func pairKey(
        originalText: String,
        correctedText: String
    ) -> String {
        WordReplacementVariants.key(for: originalText) + "\u{0}"
            + WordReplacementVariants.destinationKey(for: correctedText)
    }
}
