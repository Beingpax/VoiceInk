import Foundation

struct TranscriptionSegment: Identifiable, Codable, Equatable {
    let id: Int
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Double?

    init(id: Int, text: String, startTime: TimeInterval, endTime: TimeInterval, confidence: Double?) {
        self.id = id
        self.text = text
        self.startTime = max(0, startTime)
        self.endTime = max(startTime, endTime)
        self.confidence = confidence
    }
}

struct TranscriptionSummaryAction: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let ownerHint: String?
    let dueDateHint: String?

    init(id: UUID = UUID(), text: String, ownerHint: String?, dueDateHint: String?) {
        self.id = id
        self.text = text
        self.ownerHint = ownerHint
        self.dueDateHint = dueDateHint
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case ownerHint
        case dueDateHint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.text = try container.decode(String.self, forKey: .text)
        self.ownerHint = try container.decodeIfPresent(String.self, forKey: .ownerHint)
        self.dueDateHint = try container.decodeIfPresent(String.self, forKey: .dueDateHint)
        self.id = UUID()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(ownerHint, forKey: .ownerHint)
        try container.encodeIfPresent(dueDateHint, forKey: .dueDateHint)
    }
}

struct TranscriptionScheduleRecommendation: Codable, Equatable {
    let title: String
    let startWindow: String?
    let durationMinutes: Int?
    let participants: [String]?
}

struct TranscriptionSummaryBlock: Codable, Equatable {
    let summary: String
    let actionItems: [TranscriptionSummaryAction]
    let scheduleRecommendation: TranscriptionScheduleRecommendation?
}

struct TranscriptCleanupResult: Codable, Equatable {
    let instruction: String
    let label: String?
    let output: String
}

struct TranscriptionRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let createdAt: Date
    let title: String
    let transcript: String
    let language: String?
    let duration: TimeInterval
    let segments: [TranscriptionSegment]
    let summary: TranscriptionSummaryBlock?
    let cleanup: TranscriptCleanupResult?

    init(id: UUID = UUID(),
         createdAt: Date = Date(),
         title: String,
         transcript: String,
         language: String?,
         duration: TimeInterval,
         segments: [TranscriptionSegment],
         summary: TranscriptionSummaryBlock?,
         cleanup: TranscriptCleanupResult?) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.transcript = transcript
        self.language = language
        self.duration = duration
        self.segments = segments
        self.summary = summary
        self.cleanup = cleanup
    }
}

extension TranscriptionSummaryBlock {
    var isMeaningful: Bool {
        let hasSummary = !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasActions = !actionItems.isEmpty
        return hasSummary || hasActions || scheduleRecommendation != nil
    }
}
