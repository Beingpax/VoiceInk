import Foundation
import OSLog
import SwiftData

struct TranscriptionCleanupResult: Sendable {
    let deletedCount: Int
    let audioFileErrorCount: Int
    let errorMessage: String?
}

private struct TranscriptionSweepResult: Sendable {
    var deletedIDs = Set<UUID>()
    var audioFileErrorCount = 0
    var errorMessage: String?
}

@ModelActor
private actor TranscriptionCleanupWorker {
    private static let batchSize = 1_000

    private let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "TranscriptionAutoCleanupService"
    )

    func sweep(cutoffDate: Date) -> TranscriptionSweepResult {
        var result = TranscriptionSweepResult()

        while true {
            do {
                let batchResult = try autoreleasepool {
                    () throws -> (fetchedCount: Int, deletedIDs: Set<UUID>, audioFileErrorCount: Int) in
                    let batchContext = ModelContext(modelContainer)
                    var descriptor = FetchDescriptor<Transcription>(
                        predicate: #Predicate<Transcription> { transcription in
                            transcription.timestamp < cutoffDate
                        },
                        sortBy: [SortDescriptor(\.id)]
                    )
                    descriptor.fetchLimit = Self.batchSize

                    let transcriptions = try batchContext.fetch(descriptor)
                    let deletedIDs = Set(transcriptions.map(\.id))
                    let audioURLs = transcriptions.compactMap {
                        $0.audioFileURL.flatMap(URL.init(string:))
                    }

                    for transcription in transcriptions {
                        batchContext.delete(transcription)
                    }

                    if !deletedIDs.isEmpty {
                        try batchContext.save()
                    }

                    var audioFileErrorCount = 0
                    for audioURL in audioURLs where FileManager.default.fileExists(atPath: audioURL.path) {
                        do {
                            try FileManager.default.removeItem(at: audioURL)
                        } catch {
                            audioFileErrorCount += 1
                            logger.error(
                                "Failed to delete audio file during transcript cleanup: \(error, privacy: .public)"
                            )
                        }
                    }

                    return (transcriptions.count, deletedIDs, audioFileErrorCount)
                }

                result.deletedIDs.formUnion(batchResult.deletedIDs)
                result.audioFileErrorCount += batchResult.audioFileErrorCount

                if batchResult.fetchedCount < Self.batchSize {
                    return result
                }
            } catch {
                logger.error("Failed to fetch or save a transcript cleanup batch: \(error, privacy: .public)")
                result.errorMessage = String(
                    localized: "VoiceInk couldn't finish deleting transcript history. Try again or export logs from Settings."
                )
                return result
            }
        }
    }

    /// Removes only stale, unreferenced recordings. The age check protects active recordings
    /// and files that have been created for an in-progress transcription.
    func cleanupOrphanAudioFiles(in recordingsDirectory: URL, olderThan cutoffDate: Date) {
        do {
            let referenceContext = ModelContext(modelContainer)
            var descriptor = FetchDescriptor<Transcription>()
            descriptor.propertiesToFetch = [\.audioFileURL]
            let transcriptions = try referenceContext.fetch(descriptor)
            let referencedFiles = Set(transcriptions.compactMap { transcription -> String? in
                guard let urlString = transcription.audioFileURL,
                    let url = URL(string: urlString)
                else { return nil }
                return url.lastPathComponent
            })

            guard FileManager.default.fileExists(atPath: recordingsDirectory.path) else { return }
            guard let files = FileManager.default.enumerator(
                at: recordingsDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            ) else { return }

            var deletedCount = 0
            for case let fileURL as URL in files
            where !referencedFiles.contains(fileURL.lastPathComponent) {
                do {
                    let values = try fileURL.resourceValues(
                        forKeys: [.contentModificationDateKey, .creationDateKey, .isRegularFileKey]
                    )
                    guard values.isRegularFile == true,
                        let fileDate = values.contentModificationDate ?? values.creationDate,
                        fileDate < cutoffDate
                    else { continue }

                    try FileManager.default.removeItem(at: fileURL)
                    deletedCount += 1
                } catch {
                    logger.error("Failed to inspect or delete orphan audio file: \(error, privacy: .public)")
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
        let transcriptionID = transcription.id

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
            Notification.postTranscriptionDeleted(ids: [transcriptionID])
        } catch {
            modelContext.rollback()
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

        let result = await worker.sweep(cutoffDate: cutoffDate)
        if !result.deletedIDs.isEmpty {
            logger.notice("Cleaned up \(result.deletedIDs.count, privacy: .public) old transcription(s)")
            Notification.postTranscriptionDeleted(ids: result.deletedIDs)
        }
        return TranscriptionCleanupResult(
            deletedCount: result.deletedIDs.count,
            audioFileErrorCount: result.audioFileErrorCount,
            errorMessage: result.errorMessage
        )
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
