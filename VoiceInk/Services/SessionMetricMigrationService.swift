import Foundation
import SwiftData
import OSLog

@MainActor
final class SessionMetricMigrationService {
    static let shared = SessionMetricMigrationService()

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "SessionMetricMigrationService")
    private let completionKey = "HasCompletedStatsMigration"
    private let tokenBackfillCompletionKey = "HasCompletedStatsTokenBackfillV2"
    private(set) var isStatsMigrationRunning = false
    private(set) var isTokenBackfillRunning = false

    var isRunning: Bool {
        isStatsMigrationRunning || isTokenBackfillRunning
    }

    private init() {}

    @discardableResult
    func runStatsMigrationIfNeeded(modelContainer: ModelContainer) -> Task<Void, Never>? {
        guard !UserDefaults.standard.bool(forKey: completionKey), !isStatsMigrationRunning else { return nil }
        isStatsMigrationRunning = true

        let logger = self.logger
        let completionKey = self.completionKey

        return Task.detached(priority: .utility) {
            let backgroundContext = ModelContext(modelContainer)
            var insertedCount = 0

            do {
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

                    let metric = Self.makeSessionMetric(from: transcription)
                    backgroundContext.insert(metric)
                    insertedCount += 1
                }

                if insertedCount > 0 {
                    try backgroundContext.save()
                }

                UserDefaults.standard.set(true, forKey: completionKey)
                logger.notice("Completed stats migration with \(insertedCount, privacy: .public) inserted session metric(s)")
            } catch {
                logger.error("Stats migration failed: \(error, privacy: .public)")
            }

            await MainActor.run {
                SessionMetricMigrationService.shared.isStatsMigrationRunning = false
                NotificationCenter.default.post(name: .sessionMetricsDidChange, object: nil)
            }
        }
    }

    @discardableResult
    func runEnhancementTokenBackfillIfNeeded(modelContainer: ModelContainer) -> Task<Void, Never>? {
        guard !UserDefaults.standard.bool(forKey: tokenBackfillCompletionKey), !isTokenBackfillRunning else { return nil }
        isTokenBackfillRunning = true

        let logger = self.logger
        let tokenBackfillCompletionKey = self.tokenBackfillCompletionKey

        return Task.detached(priority: .utility) {
            let backgroundContext = ModelContext(modelContainer)
            var updatedCount = 0

            do {
                var metricsByTranscriptionId: [UUID: SessionMetric] = [:]
                for metric in try backgroundContext.fetch(FetchDescriptor<SessionMetric>()) {
                    if metricsByTranscriptionId[metric.transcriptionId] == nil {
                        metricsByTranscriptionId[metric.transcriptionId] = metric
                    }
                }

                let descriptor = FetchDescriptor<Transcription>(
                    predicate: #Predicate<Transcription> { $0.transcriptionStatus == "completed" }
                )
                let transcriptions = try backgroundContext.fetch(descriptor)

                for transcription in transcriptions {
                    guard let metric = metricsByTranscriptionId[transcription.id] else { continue }
                    if Self.applyEnhancementTokenEstimate(to: metric, from: transcription) {
                        updatedCount += 1
                    }
                }

                if updatedCount > 0 {
                    try backgroundContext.save()
                }

                UserDefaults.standard.set(true, forKey: tokenBackfillCompletionKey)
                logger.notice("Completed enhancement token backfill with \(updatedCount, privacy: .public) updated session metric(s)")
            } catch {
                logger.error("Enhancement token backfill failed: \(error, privacy: .public)")
            }

            await MainActor.run {
                SessionMetricMigrationService.shared.isTokenBackfillRunning = false
                NotificationCenter.default.post(name: .sessionMetricsDidChange, object: nil)
            }
        }
    }

    nonisolated private static func makeSessionMetric(from transcription: Transcription) -> SessionMetric {
        let enhancementDuration = positiveDuration(transcription.enhancementDuration)
        let audioDuration = max(transcription.duration, 0)
        let transcriptionDuration = positiveDuration(transcription.transcriptionDuration)
        let speedFactor = transcriptionDuration.flatMap { duration in
            audioDuration > 0 ? audioDuration / duration : nil
        }
        let enhancementTokenEstimate = EnhancementTokenEstimate.estimate(from: transcription)

        return SessionMetric(
            transcriptionId: transcription.id,
            timestamp: transcription.timestamp,
            source: "recorder",
            wordCount: WordCounter.count(in: textForCounting(from: transcription)),
            audioDuration: audioDuration,
            transcriptionModelName: transcription.transcriptionModelName,
            transcriptionDuration: transcriptionDuration,
            speedFactor: speedFactor,
            modeName: transcription.modeName,
            aiEnhancementModelName: transcription.aiEnhancementModelName,
            enhancementDuration: enhancementDuration,
            enhancementEstimatedTokenCount: enhancementTokenEstimate?.tokenCount
        )
    }

    nonisolated private static func applyEnhancementTokenEstimate(
        to metric: SessionMetric,
        from transcription: Transcription
    ) -> Bool {
        guard let estimate = EnhancementTokenEstimate.estimate(from: transcription) else {
            return false
        }

        var didUpdate = false
        if metric.enhancementEstimatedTokenCount != estimate.tokenCount {
            metric.enhancementEstimatedTokenCount = estimate.tokenCount
            didUpdate = true
        }

        return didUpdate
    }

    nonisolated private static func textForCounting(from transcription: Transcription) -> String {
        if let enhancedText = transcription.enhancedText,
           transcription.enhancementDuration != nil,
           !enhancedText.isEmpty {
            return enhancedText
        }

        return transcription.text
    }

    nonisolated private static func positiveDuration(_ duration: TimeInterval?) -> TimeInterval? {
        duration.flatMap { $0 > 0 ? $0 : nil }
    }
}
