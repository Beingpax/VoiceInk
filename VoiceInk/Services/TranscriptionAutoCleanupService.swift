import Foundation
import OSLog
import SwiftData

struct TranscriptionCleanupResult: Sendable {
    let deletedCount: Int
    let audioFileErrorCount: Int
    let errorMessage: String?
}

@ModelActor
private actor TranscriptionCleanupWorker {
    private static let batchSize = 1_000
    private static let referenceBatchSize = 10_000

    private let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "TranscriptionAutoCleanupService"
    )

    func sweep(cutoffDate: Date) throws -> (deletedCount: Int, audioFileErrorCount: Int) {
        var deletedCount = 0
        var audioFileErrorCount = 0

        while true {
            let batchResult = try autoreleasepool { () throws -> (deletedCount: Int, audioFileErrorCount: Int) in
                let batchContext = ModelContext(modelContainer)
                var descriptor = FetchDescriptor<Transcription>(
                    predicate: #Predicate<Transcription> { transcription in
                        transcription.timestamp < cutoffDate
                    }
                )
                descriptor.fetchLimit = Self.batchSize

                let transcriptions = try batchContext.fetch(descriptor)
                let audioURLs = transcriptions.compactMap { transcription -> URL? in
                    guard let urlString = transcription.audioFileURL else { return nil }
                    return URL(string: urlString)
                }

                for transcription in transcriptions {
                    batchContext.delete(transcription)
                }

                if !transcriptions.isEmpty {
                    try batchContext.save()
                }

                var batchAudioFileErrorCount = 0
                for audioURL in audioURLs where FileManager.default.fileExists(atPath: audioURL.path) {
                    do {
                        try FileManager.default.removeItem(at: audioURL)
                    } catch {
                        batchAudioFileErrorCount += 1
                        logger.error(
                            "Failed to delete audio file during transcript cleanup: \(error, privacy: .public)"
                        )
                    }
                }

                return (
                    deletedCount: transcriptions.count,
                    audioFileErrorCount: batchAudioFileErrorCount
                )
            }

            deletedCount += batchResult.deletedCount
            audioFileErrorCount += batchResult.audioFileErrorCount

            if batchResult.deletedCount < Self.batchSize {
                break
            }
        }

        return (
            deletedCount: deletedCount,
            audioFileErrorCount: audioFileErrorCount
        )
    }

    /// Removes only stale, unreferenced recordings. The age check protects active recordings
    /// and files that have been created for an in-progress transcription.
    func cleanupOrphanAudioFiles(in recordingsDirectory: URL, olderThan cutoffDate: Date) {
        do {
            var referencedFiles = Set<String>()
            var fetchOffset = 0

            while true {
                let batch = try autoreleasepool { () throws -> (fetchedCount: Int, fileNames: [String]) in
                    let batchContext = ModelContext(modelContainer)
                    var descriptor = FetchDescriptor<Transcription>(
                        sortBy: [SortDescriptor(\.id)]
                    )
                    descriptor.propertiesToFetch = [\.audioFileURL]
                    descriptor.fetchLimit = Self.referenceBatchSize
                    descriptor.fetchOffset = fetchOffset

                    let transcriptions = try batchContext.fetch(descriptor)
                    let fileNames = transcriptions.compactMap { transcription in
                        guard let urlString = transcription.audioFileURL,
                            let url = URL(string: urlString)
                        else { return nil }
                        return url.lastPathComponent
                    }
                    return (transcriptions.count, fileNames)
                }

                referencedFiles.formUnion(batch.fileNames)
                fetchOffset += batch.fetchedCount

                if batch.fetchedCount < Self.referenceBatchSize {
                    break
                }
            }

            guard FileManager.default.fileExists(atPath: recordingsDirectory.path) else { return }
            guard let files = FileManager.default.enumerator(
                at: recordingsDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            ) else { return }

            var deletedCount = 0
            for case let fileURL as URL in files
            where !referencedFiles.contains(fileURL.lastPathComponent) {
                let values = try fileURL.resourceValues(
                    forKeys: [.contentModificationDateKey, .creationDateKey, .isRegularFileKey]
                )
                guard values.isRegularFile == true,
                    let fileDate = values.contentModificationDate ?? values.creationDate,
                    fileDate < cutoffDate
                else { continue }

                do {
                    try FileManager.default.removeItem(at: fileURL)
                    deletedCount += 1
                } catch {
                    logger.error("Failed to delete orphan audio file: \(error, privacy: .public)")
                }
            }

            if deletedCount > 0 {
                logger.notice("Cleaned up \(deletedCount, privacy: .public) stale orphan audio file(s)")
            }
        } catch {
            logger.error("Failed during orphan audio cleanup: \(error, privacy: .public)")
        }
    }
}

@MainActor
final class TranscriptionAutoCleanupService {
    static let shared = TranscriptionAutoCleanupService()

    private static let orphanFileGracePeriod: TimeInterval = 7 * 24 * 60 * 60

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "TranscriptionAutoCleanupService")
    private var modelContext: ModelContext?
    private var cleanupWorker: TranscriptionCleanupWorker?

    private var recordingsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.prakashjoshipax.VoiceInk")
            .appendingPathComponent("Recordings")
    }

    private init() {}

    func startMonitoring(modelContext: ModelContext) {
        self.modelContext = modelContext
        cleanupWorker = TranscriptionCleanupWorker(modelContainer: modelContext.container)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTranscriptionCompleted(_:)),
            name: .transcriptionCompleted,
            object: nil
        )

        if UserDefaults.standard.bool(forKey: CleanupSettingsKeys.isTranscriptionCleanupEnabled) {
            Task { [weak self] in
                guard let self, let modelContext = self.modelContext else { return }
                _ = await self.sweepOldTranscriptions(modelContext: modelContext)
                await self.cleanupOrphanAudioFiles(modelContext: modelContext)
            }
        }
    }

    func stopMonitoring() {
        NotificationCenter.default.removeObserver(self, name: .transcriptionCompleted, object: nil)
    }

    func runManualCleanup(modelContext: ModelContext) async -> TranscriptionCleanupResult {
        await sweepOldTranscriptions(modelContext: modelContext)
    }

    @objc private func handleTranscriptionCompleted(_ notification: Notification) {
        let isEnabled = UserDefaults.standard.bool(forKey: CleanupSettingsKeys.isTranscriptionCleanupEnabled)
        guard isEnabled else { return }

        let minutes = UserDefaults.standard.integer(forKey: CleanupSettingsKeys.transcriptionRetentionMinutes)
        if minutes > 0 {
            if let modelContext = self.modelContext {
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    _ = await self.sweepOldTranscriptions(modelContext: modelContext)
                }
            }
            return
        }

        guard let transcription = notification.object as? Transcription,
            let modelContext = self.modelContext
        else {
            logger.error("Invalid transcription or missing model context")
            return
        }

        let audioURL = transcription.audioFileURL.flatMap(URL.init(string:))

        modelContext.delete(transcription)

        do {
            try modelContext.save()
            if let audioURL, FileManager.default.fileExists(atPath: audioURL.path) {
                do {
                    try FileManager.default.removeItem(at: audioURL)
                } catch {
                    logger.error("Failed to delete audio file: \(error, privacy: .public)")
                }
            }
            NotificationCenter.default.post(name: .transcriptionDeleted, object: nil)
        } catch {
            logger.error("Failed to save after transcription deletion: \(error, privacy: .public)")
        }
    }

    private func sweepOldTranscriptions(modelContext: ModelContext) async -> TranscriptionCleanupResult {
        guard UserDefaults.standard.bool(forKey: CleanupSettingsKeys.isTranscriptionCleanupEnabled) else {
            return TranscriptionCleanupResult(
                deletedCount: 0,
                audioFileErrorCount: 0,
                errorMessage: String(localized: "Transcript auto-delete is turned off.")
            )
        }

        let retentionMinutes = UserDefaults.standard.integer(forKey: CleanupSettingsKeys.transcriptionRetentionMinutes)
        let effectiveMinutes = max(retentionMinutes, 0)

        let cutoffDate = Date().addingTimeInterval(TimeInterval(-effectiveMinutes * 60))

        let worker = cleanupWorker ?? TranscriptionCleanupWorker(modelContainer: modelContext.container)
        cleanupWorker = worker

        do {
            let result = try await worker.sweep(cutoffDate: cutoffDate)
            if result.deletedCount > 0 {
                logger.notice("Cleaned up \(result.deletedCount, privacy: .public) old transcription(s)")
                NotificationCenter.default.post(name: .transcriptionDeleted, object: nil)
            }
            return TranscriptionCleanupResult(
                deletedCount: result.deletedCount,
                audioFileErrorCount: result.audioFileErrorCount,
                errorMessage: nil
            )
        } catch {
            logger.error("Failed during transcription cleanup: \(error, privacy: .public)")
            return TranscriptionCleanupResult(
                deletedCount: 0,
                audioFileErrorCount: 0,
                errorMessage: String(localized: "VoiceInk couldn't delete transcript history. Try again or export logs from Settings.")
            )
        }
    }

    /// Deletes audio files in Recordings directory that have no corresponding Transcription record
    private func cleanupOrphanAudioFiles(modelContext: ModelContext) async {
        guard UserDefaults.standard.bool(forKey: CleanupSettingsKeys.isTranscriptionCleanupEnabled) else {
            return
        }

        let worker = cleanupWorker ?? TranscriptionCleanupWorker(modelContainer: modelContext.container)
        cleanupWorker = worker
        let cutoffDate = Date().addingTimeInterval(-Self.orphanFileGracePeriod)
        await worker.cleanupOrphanAudioFiles(in: recordingsDirectory, olderThan: cutoffDate)
    }
}
