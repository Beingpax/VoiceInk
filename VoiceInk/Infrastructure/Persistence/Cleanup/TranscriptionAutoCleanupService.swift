import Foundation
import OSLog
import SwiftData

@MainActor
final class TranscriptionAutoCleanupService {
    static let shared = TranscriptionAutoCleanupService()

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "TranscriptionAutoCleanupService")
    private var modelContext: ModelContext?

    private var recordingsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.prakashjoshipax.VoiceInk")
            .appendingPathComponent("Recordings")
    }

    private init() {}

    func startMonitoring(modelContext: ModelContext) {
        self.modelContext = modelContext

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTranscriptionCompleted(_:)),
            name: .transcriptionCompleted,
            object: nil
        )

        if UserDefaults.standard.bool(forKey: CleanupSettingsKeys.isTranscriptionCleanupEnabled) {
            let modelContainer = modelContext.container
            Task { [weak self] in
                let worker = await Self.makeWorker(modelContainer: modelContainer)
                guard let self else { return }
                await self.sweepOldTranscriptions(worker: worker)
                await self.cleanupOrphanAudioFiles(worker: worker)
            }
        }
    }

    func stopMonitoring() {
        NotificationCenter.default.removeObserver(self, name: .transcriptionCompleted, object: nil)
    }

    func runManualCleanup(modelContext: ModelContext) async {
        let worker = await Self.makeWorker(modelContainer: modelContext.container)
        await sweepOldTranscriptions(worker: worker)
    }

    @objc private func handleTranscriptionCompleted(_ notification: Notification) {
        let isEnabled = UserDefaults.standard.bool(forKey: CleanupSettingsKeys.isTranscriptionCleanupEnabled)
        guard isEnabled else { return }

        let minutes = UserDefaults.standard.integer(forKey: CleanupSettingsKeys.transcriptionRetentionMinutes)
        if minutes > 0 {
            if let modelContext = self.modelContext {
                let modelContainer = modelContext.container
                Task { [weak self] in
                    let worker = await Self.makeWorker(modelContainer: modelContainer)
                    await self?.sweepOldTranscriptions(worker: worker)
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

        if let urlString = transcription.audioFileURL,
            let url = URL(string: urlString)
        {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                logger.error("Failed to delete audio file: \(error, privacy: .public)")
            }
        }

        modelContext.delete(transcription)

        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .transcriptionDeleted, object: nil)
        } catch {
            logger.error("Failed to save after transcription deletion: \(error, privacy: .public)")
        }
    }

    private func sweepOldTranscriptions(worker: TranscriptionCleanupWorker) async {
        guard UserDefaults.standard.bool(forKey: CleanupSettingsKeys.isTranscriptionCleanupEnabled) else {
            return
        }

        let retentionMinutes = UserDefaults.standard.integer(forKey: CleanupSettingsKeys.transcriptionRetentionMinutes)
        let effectiveMinutes = max(retentionMinutes, 0)

        let cutoffDate = Date().addingTimeInterval(TimeInterval(-effectiveMinutes * 60))

        do {
            let deletedCount = try await worker.sweepOldTranscriptions(before: cutoffDate)
            if deletedCount > 0 {
                logger.notice("Cleaned up \(deletedCount, privacy: .public) old transcription(s)")
                NotificationCenter.default.post(name: .transcriptionDeleted, object: nil)
            }
        } catch {
            logger.error("Failed during transcription cleanup: \(error, privacy: .public)")
        }
    }

    /// Deletes audio files in Recordings directory that have no corresponding Transcription record
    private func cleanupOrphanAudioFiles(worker: TranscriptionCleanupWorker) async {
        guard UserDefaults.standard.bool(forKey: CleanupSettingsKeys.isTranscriptionCleanupEnabled) else {
            return
        }

        do {
            let deletedCount = try await worker.cleanupOrphanAudioFiles(in: recordingsDirectory)
            if deletedCount > 0 {
                logger.notice("Cleaned up \(deletedCount, privacy: .public) orphan audio file(s)")
            }
        } catch {
            logger.error("Failed during orphan audio cleanup: \(error, privacy: .public)")
        }
    }

    private nonisolated static func makeWorker(
        modelContainer: ModelContainer
    ) async -> TranscriptionCleanupWorker {
        await Task.detached(priority: .utility) {
            TranscriptionCleanupWorker(modelContainer: modelContainer)
        }.value
    }
}

@ModelActor
private actor TranscriptionCleanupWorker {
    func sweepOldTranscriptions(before cutoffDate: Date) throws -> Int {
        let descriptor = FetchDescriptor<Transcription>(
            predicate: #Predicate<Transcription> { transcription in
                transcription.timestamp < cutoffDate
            }
        )
        let transcriptions = try modelContext.fetch(descriptor)

        for transcription in transcriptions {
            if let urlString = transcription.audioFileURL,
                let url = URL(string: urlString),
                FileManager.default.fileExists(atPath: url.path)
            {
                try? FileManager.default.removeItem(at: url)
            }
            modelContext.delete(transcription)
        }

        if !transcriptions.isEmpty {
            try modelContext.save()
        }
        return transcriptions.count
    }

    func cleanupOrphanAudioFiles(in recordingsDirectory: URL) throws -> Int {
        var descriptor = FetchDescriptor<Transcription>()
        descriptor.propertiesToFetch = [\.audioFileURL]

        let transcriptions = try modelContext.fetch(descriptor)
        let referencedFiles = Set(
            transcriptions.compactMap { transcription -> String? in
                guard let urlString = transcription.audioFileURL,
                    let url = URL(string: urlString)
                else { return nil }
                return url.lastPathComponent
            })

        guard FileManager.default.fileExists(atPath: recordingsDirectory.path) else { return 0 }
        let filesInDirectory = try FileManager.default.contentsOfDirectory(
            at: recordingsDirectory,
            includingPropertiesForKeys: nil
        )

        var deletedCount = 0
        for fileURL in filesInDirectory where !referencedFiles.contains(fileURL.lastPathComponent) {
            do {
                try FileManager.default.removeItem(at: fileURL)
                deletedCount += 1
            } catch {
                // Orphan cleanup is best-effort; continue with the remaining files.
            }
        }
        return deletedCount
    }
}
