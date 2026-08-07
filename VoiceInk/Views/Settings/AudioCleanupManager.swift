import Foundation
import SwiftData

/// A utility class that manages automatic cleanup of audio files while preserving transcript data.
/// SwiftData models are main-actor bound, so the whole manager is isolated rather than hopping.
@MainActor
class AudioCleanupManager {
    static let shared = AudioCleanupManager()

    nonisolated(unsafe) private var cleanupTask: Task<Void, Never>?
    private let cleanupCheckInterval: TimeInterval = 86400  // Check once per day (in seconds)

    private init() {}

    /// Start the automatic cleanup schedule.
    ///
    /// Uses a main-actor task rather than a `Timer` so `modelContext` — which is not Sendable —
    /// never leaves this isolation domain, and so cancellation is structured.
    func startAutomaticCleanup(modelContext: ModelContext) {
        cleanupTask?.cancel()

        cleanupTask = Task { [weak self] in
            guard let interval = self?.cleanupCheckInterval else { return }

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                await self?.runAutomaticCleanupIfNeeded(modelContext: modelContext)
            }
        }
    }

    /// Run automatic cleanup once if it is due. This is safe to call on app/window appear.
    func runAutomaticCleanupIfNeeded(modelContext: ModelContext) async {
        guard UserDefaults.standard.bool(forKey: CleanupSettingsKeys.isAudioCleanupEnabled),
            !UserDefaults.standard.bool(forKey: CleanupSettingsKeys.isTranscriptionCleanupEnabled),
            shouldRunAutomaticCleanup()
        else {
            return
        }

        await performCleanup(modelContext: modelContext)
        UserDefaults.standard.set(Date(), forKey: CleanupSettingsKeys.lastAutomaticAudioCleanupDate)
    }

    /// Stop the automatic cleanup process
    func stopAutomaticCleanup() {
        cleanupTask?.cancel()
        cleanupTask = nil
    }

    /// Get information about the files that would be cleaned up
    func getCleanupInfo(modelContext: ModelContext) async -> (
        fileCount: Int, totalSize: Int64, transcriptions: [Transcription]
    ) {
        // Get retention period from UserDefaults
        let effectiveRetentionDays = UserDefaults.standard.integer(forKey: CleanupSettingsKeys.audioRetentionPeriod)

        // Calculate the cutoff date
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -effectiveRetentionDays, to: Date()) else {
            return (0, 0, [])
        }

        do {
            // Already on the main actor: SwiftData models never leave this isolation domain.
            // Create a predicate to find transcriptions with audio files older than the cutoff date
            let descriptor = FetchDescriptor<Transcription>(
                predicate: #Predicate<Transcription> { transcription in
                    transcription.timestamp < cutoffDate && transcription.audioFileURL != nil
                }
            )

            let transcriptions = try modelContext.fetch(descriptor)

            // Calculate stats (can be done on any thread)
            var fileCount = 0
            var totalSize: Int64 = 0
            var eligibleTranscriptions: [Transcription] = []

            for transcription in transcriptions {
                if let urlString = transcription.audioFileURL,
                    let url = URL(string: urlString),
                    FileManager.default.fileExists(atPath: url.path)
                {
                    if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                        let fileSize = attributes[.size] as? Int64
                    {
                        totalSize += fileSize
                        fileCount += 1
                        eligibleTranscriptions.append(transcription)
                    }
                }
            }

            return (fileCount, totalSize, eligibleTranscriptions)
        } catch {
            return (0, 0, [])
        }
    }

    /// Perform the cleanup operation
    private func performCleanup(modelContext: ModelContext) async {
        // Get retention period from UserDefaults
        let effectiveRetentionDays = UserDefaults.standard.integer(forKey: CleanupSettingsKeys.audioRetentionPeriod)

        // Check if automatic cleanup is enabled
        let isCleanupEnabled = UserDefaults.standard.bool(forKey: CleanupSettingsKeys.isAudioCleanupEnabled)
        guard isCleanupEnabled else { return }

        // Calculate the cutoff date
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -effectiveRetentionDays, to: Date()) else {
            return
        }

        do {
            // Already on the main actor: SwiftData models never leave this isolation domain.
            // Create a predicate to find transcriptions with audio files older than the cutoff date
            let descriptor = FetchDescriptor<Transcription>(
                predicate: #Predicate<Transcription> { transcription in
                    transcription.timestamp < cutoffDate && transcription.audioFileURL != nil
                }
            )

            let transcriptions = try modelContext.fetch(descriptor)
            var deletedCount = 0

            for transcription in transcriptions {
                if let urlString = transcription.audioFileURL,
                    let url = URL(string: urlString),
                    FileManager.default.fileExists(atPath: url.path)
                {
                    do {
                        try FileManager.default.removeItem(at: url)
                        transcription.audioFileURL = nil
                        deletedCount += 1
                    } catch {
                        // Skip this file - don't update audioFileURL if deletion failed
                    }
                }
            }

            if deletedCount > 0 {
                try modelContext.save()
            }
        } catch {
            // Silently fail - cleanup is non-critical
        }
    }

    /// Run cleanup manually - can be called from settings
    func runManualCleanup(modelContext: ModelContext) async {
        await performCleanup(modelContext: modelContext)
    }

    private func shouldRunAutomaticCleanup() -> Bool {
        guard
            let lastCleanupDate = UserDefaults.standard.object(
                forKey: CleanupSettingsKeys.lastAutomaticAudioCleanupDate) as? Date
        else {
            return true
        }

        return Date().timeIntervalSince(lastCleanupDate) >= cleanupCheckInterval
    }

    /// Run cleanup on the specified transcriptions
    func runCleanupForTranscriptions(modelContext: ModelContext, transcriptions: [Transcription]) async -> (
        deletedCount: Int, errorCount: Int
    ) {
        do {
            // Already on the main actor: SwiftData models never leave this isolation domain.
            var deletedCount = 0
            var errorCount = 0

            for transcription in transcriptions {
                if let urlString = transcription.audioFileURL,
                    let url = URL(string: urlString),
                    FileManager.default.fileExists(atPath: url.path)
                {
                    do {
                        try FileManager.default.removeItem(at: url)
                        transcription.audioFileURL = nil
                        deletedCount += 1
                    } catch {
                        errorCount += 1
                    }
                }
            }

            if deletedCount > 0 || errorCount > 0 {
                try? modelContext.save()
            }

            return (deletedCount, errorCount)
        } catch {
            return (0, 0)
        }
    }

    /// Format file size in human-readable form
    func formatFileSize(_ size: Int64) -> String {
        let byteCountFormatter = ByteCountFormatter()
        byteCountFormatter.allowedUnits = [.useKB, .useMB, .useGB]
        byteCountFormatter.countStyle = .file
        return byteCountFormatter.string(fromByteCount: size)
    }
}
