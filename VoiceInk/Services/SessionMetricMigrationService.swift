import Foundation
import SwiftData
import OSLog

@MainActor
final class SessionMetricMigrationService {
    static let shared = SessionMetricMigrationService()

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "SessionMetricMigrationService")
    private let completionKey = "HasCompletedStatsMigration"
    private(set) var isRunning = false

    private init() {}

    @discardableResult
    func runIfNeeded(modelContainer: ModelContainer) -> Task<Void, Never>? {
        guard !UserDefaults.standard.bool(forKey: completionKey), !isRunning else { return nil }
        isRunning = true

        let logger = self.logger
        let completionKey = self.completionKey

        return Task.detached(priority: .utility) {
            let backgroundContext = ModelContext(modelContainer)
            var insertedCount = 0

            do {
                // Build a Set of already-migrated IDs in one query instead of
                // checking per-record — turns N queries into 1.
                let existingIds = Set(
                    try backgroundContext.fetch(FetchDescriptor<SessionMetric>())
                        .map { $0.transcriptionId }
                )

                let descriptor = FetchDescriptor<Transcription>(
                    predicate: #Predicate<Transcription> { $0.transcriptionStatus == "completed" }
                )
                let transcriptions = try backgroundContext.fetch(descriptor)

                for transcription in transcriptions {
                    guard !existingIds.contains(transcription.id) else { continue }

                    let enhancementDuration = transcription.enhancementDuration.flatMap { $0 > 0 ? $0 : nil }
                    let audioDuration = max(transcription.duration, 0)
                    let transcriptionDuration = transcription.transcriptionDuration.flatMap { $0 > 0 ? $0 : nil }
                    let speedFactor = transcriptionDuration.flatMap { d in
                        audioDuration > 0 ? audioDuration / d : nil
                    }
                    let textForCounting: String = {
                        if let enhanced = transcription.enhancedText,
                           transcription.enhancementDuration != nil,
                           !enhanced.isEmpty { return enhanced }
                        return transcription.text
                    }()

                    let metric = SessionMetric(
                        transcriptionId: transcription.id,
                        timestamp: transcription.timestamp,
                        source: "recorder",
                        wordCount: WordCounter.count(in: textForCounting),
                        audioDuration: audioDuration,
                        transcriptionModelName: transcription.transcriptionModelName,
                        transcriptionDuration: transcriptionDuration,
                        speedFactor: speedFactor,
                        powerModeName: transcription.powerModeName,
                        aiEnhancementModelName: transcription.aiEnhancementModelName,
                        enhancementDuration: enhancementDuration
                    )
                    backgroundContext.insert(metric)
                    insertedCount += 1
                }

                if insertedCount > 0 {
                    try backgroundContext.save()
                }

                UserDefaults.standard.set(true, forKey: completionKey)
                logger.notice("Completed stats migration with \(insertedCount, privacy: .public) session metric(s)")
            } catch {
                logger.error("Stats migration failed: \(error.localizedDescription, privacy: .public)")
            }

            await MainActor.run {
                SessionMetricMigrationService.shared.isRunning = false
                NotificationCenter.default.post(name: .sessionMetricsDidChange, object: nil)
            }
        }
    }
}
