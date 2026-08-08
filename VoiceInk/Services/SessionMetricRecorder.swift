import Foundation
import OSLog
import SwiftData

enum SessionMetricRecorder {
    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "SessionMetricRecorder")
    private static let source = "recorder"

    /// Flags the session behind a transcript as undone.
    ///
    /// Best-effort by design: the metric may legitimately not exist — a failed or canceled take
    /// never gets one — and an undo that cannot be attributed is not worth surfacing an error for.
    static func markUndone(transcriptionID: UUID, in modelContext: ModelContext) {
        let descriptor = FetchDescriptor<SessionMetric>(
            predicate: #Predicate<SessionMetric> { $0.transcriptionId == transcriptionID }
        )
        do {
            guard let metric = try modelContext.fetch(descriptor).first else { return }
            metric.wasUndone = true
            try modelContext.save()
            NotificationCenter.default.post(name: .sessionMetricsDidChange, object: nil)
        } catch {
            logger.error("Failed to mark session undone: \(error, privacy: .public)")
        }
    }

    @discardableResult
    static func recordRecorderSession(
        transcription: Transcription,
        model: (any TranscriptionModel)?,
        in modelContext: ModelContext,
        timestamp: Date = Date(),
        targetBundleIdentifier: String? = nil,
        dictionaryHitCount: Int? = nil
    ) throws -> Bool {
        guard transcription.transcriptionStatus == TranscriptionStatus.completed.rawValue else {
            return false
        }

        let transcriptionId = transcription.id
        let descriptor = FetchDescriptor<SessionMetric>(
            predicate: #Predicate<SessionMetric> { metric in
                metric.transcriptionId == transcriptionId
            }
        )

        if try modelContext.fetchCount(descriptor) > 0 {
            return false
        }

        let textForCounting = finalTextForCounting(from: transcription)
        let wordCount = WordCounter.count(in: textForCounting)
        let audioDuration = max(transcription.duration, 0)
        let transcriptionDuration = transcription.transcriptionDuration.flatMap { $0 > 0 ? $0 : nil }
        let speedFactor = transcriptionDuration.flatMap { duration in
            audioDuration > 0 ? audioDuration / duration : nil
        }

        let enhancementDuration = transcription.enhancementDuration.flatMap { $0 > 0 ? $0 : nil }
        let enhancementTokenEstimate = EnhancementTokenEstimate.estimate(from: transcription)

        let metric = SessionMetric(
            transcriptionId: transcription.id,
            timestamp: timestamp,
            source: source,
            wordCount: wordCount,
            audioDuration: audioDuration,
            transcriptionModelName: transcription.transcriptionModelName ?? model?.displayName,
            transcriptionDuration: transcriptionDuration,
            speedFactor: speedFactor,
            modeName: transcription.modeName,
            aiEnhancementModelName: transcription.aiEnhancementModelName,
            enhancementDuration: enhancementDuration,
            enhancementEstimatedTokenCount: enhancementTokenEstimate?.tokenCount,
            targetBundleIdentifier: targetBundleIdentifier,
            dictionaryHitCount: dictionaryHitCount
        )

        modelContext.insert(metric)
        logger.notice("Recorded session metric for transcription \(transcriptionId.uuidString, privacy: .public)")
        return true
    }

    private static func finalTextForCounting(from transcription: Transcription) -> String {
        if let enhancedText = transcription.enhancedText,
            transcription.enhancementDuration != nil,
            !enhancedText.isEmpty
        {
            return enhancedText
        }

        return transcription.text
    }
}
