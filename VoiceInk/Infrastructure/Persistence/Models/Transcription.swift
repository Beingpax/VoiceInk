import Foundation
import SwiftData

enum TranscriptionStatus: String, Codable {
    case pending
    case completed
    case failed
    case canceled
}

@Model
final class Transcription {
    static let canceledTranscriptionText = "The transcription was canceled."

    var id: UUID = UUID()
    var text: String = ""
    var enhancedText: String?
    var timestamp: Date = Date()
    var duration: TimeInterval = 0
    var audioFileURL: String?
    var transcriptionModelName: String?
    var aiEnhancementModelName: String?
    var promptName: String?
    var transcriptionDuration: TimeInterval?
    var enhancementDuration: TimeInterval?
    var aiRequestSystemMessage: String?
    var aiRequestUserMessage: String?
    @Attribute(originalName: "powerModeName")
    var modeName: String?
    @Attribute(originalName: "powerModeEmoji")
    var modeEmoji: String?
    var transcriptionStatus: String?
    var wordTimingsJSON: Data?
    var speakerUtterancesJSON: Data?

    init(
        text: String,
        duration: TimeInterval,
        enhancedText: String? = nil,
        audioFileURL: String? = nil,
        transcriptionModelName: String? = nil,
        aiEnhancementModelName: String? = nil,
        promptName: String? = nil,
        transcriptionDuration: TimeInterval? = nil,
        enhancementDuration: TimeInterval? = nil,
        aiRequestSystemMessage: String? = nil,
        aiRequestUserMessage: String? = nil,
        modeName: String? = nil,
        modeEmoji: String? = nil,
        transcriptionStatus: TranscriptionStatus = .pending
    ) {
        self.id = UUID()
        self.text = text
        self.enhancedText = enhancedText
        self.timestamp = Date()
        self.duration = duration
        self.audioFileURL = audioFileURL
        self.transcriptionModelName = transcriptionModelName
        self.aiEnhancementModelName = aiEnhancementModelName
        self.promptName = promptName
        self.transcriptionDuration = transcriptionDuration
        self.enhancementDuration = enhancementDuration
        self.aiRequestSystemMessage = aiRequestSystemMessage
        self.aiRequestUserMessage = aiRequestUserMessage
        self.modeName = modeName
        self.modeEmoji = modeEmoji
        self.transcriptionStatus = transcriptionStatus.rawValue
    }

    var wordTimings: [WordTiming]? {
        get { wordTimingsJSON.flatMap { try? JSONDecoder().decode([WordTiming].self, from: $0) } }
        set { wordTimingsJSON = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var speakerUtterances: [SpeakerUtterance]? {
        get { speakerUtterancesJSON.flatMap { try? JSONDecoder().decode([SpeakerUtterance].self, from: $0) } }
        set { speakerUtterancesJSON = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    /// Markdown rendering of the speaker-attributed transcript, or nil when no
    /// diarization data exists. Gaps where nobody speaks for at least
    /// `silenceThreshold` (leading, between utterances, and trailing) are
    /// rendered as Silence entries — useful for hold-time/dead-air review.
    var speakerTranscriptMarkdown: String? {
        guard let utterances = speakerUtterances, !utterances.isEmpty else { return nil }
        func label(_ id: String) -> String {
            Int(id) != nil ? "Speaker \(id)" : id.replacingOccurrences(of: "_", with: " ")
        }
        func time(_ t: TimeInterval) -> String {
            String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
        }

        let silenceThreshold: TimeInterval = {
            if let value = UserDefaults.standard.object(forKey: "TranscribeSilenceThreshold") as? Double {
                return value
            }
            return 2.0
        }()

        func silenceLine(from start: TimeInterval, to end: TimeInterval) -> String {
            "*Silence* (\(time(start))–\(time(end)), \(Int((end - start).rounded()))s)"
        }

        var lines: [String] = []
        var cursor: TimeInterval = 0
        for utterance in utterances {
            if silenceThreshold > 0, utterance.start - cursor >= silenceThreshold {
                lines.append(silenceLine(from: cursor, to: utterance.start))
            }
            lines.append(
                "**\(label(utterance.speaker))** (\(time(utterance.start))–\(time(utterance.end))): \(utterance.text)"
            )
            cursor = max(cursor, utterance.end)
        }
        if silenceThreshold > 0, duration > 0, duration - cursor >= silenceThreshold {
            lines.append(silenceLine(from: cursor, to: duration))
        }
        return lines.joined(separator: "\n\n")
    }

    func markAsCanceledTranscription(
        duration: TimeInterval? = nil,
        modelName: String? = nil
    ) {
        text = Self.canceledTranscriptionText
        enhancedText = nil
        transcriptionStatus = TranscriptionStatus.canceled.rawValue
        if let duration {
            self.duration = duration
        }
        if let modelName {
            transcriptionModelName = modelName
        }
        transcriptionDuration = nil
        enhancementDuration = nil
        aiEnhancementModelName = nil
        promptName = nil
        aiRequestSystemMessage = nil
        aiRequestUserMessage = nil
    }
}
