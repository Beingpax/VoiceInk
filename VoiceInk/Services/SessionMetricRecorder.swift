import Foundation
import SwiftData
import OSLog

enum SessionMetricRecorder {
    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "SessionMetricRecorder")
    private static let source = "recorder"

    @discardableResult
    static func recordRecorderSession(
        transcription: Transcription,
        model: (any TranscriptionModel)?,
        in modelContext: ModelContext,
        timestamp: Date = Date()
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

        let metric = SessionMetric(
            transcriptionId: transcription.id,
            timestamp: timestamp,
            source: source,
            wordCount: wordCount,
            audioDuration: audioDuration,
            transcriptionModelName: transcription.transcriptionModelName ?? model?.displayName,
            transcriptionDuration: transcriptionDuration,
            speedFactor: speedFactor,
            powerModeName: transcription.powerModeName,
            aiEnhancementModelName: transcription.aiEnhancementModelName,
            enhancementDuration: enhancementDuration
        )

        modelContext.insert(metric)
        logger.notice("Recorded session metric for transcription \(transcriptionId.uuidString, privacy: .public)")
        return true
    }

    private static func finalTextForCounting(from transcription: Transcription) -> String {
        if let enhancedText = transcription.enhancedText,
           transcription.enhancementDuration != nil,
           !enhancedText.isEmpty {
            return enhancedText
        }

        return transcription.text
    }
}
