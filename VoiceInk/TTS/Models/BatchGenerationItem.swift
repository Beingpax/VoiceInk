import Foundation

struct BatchGenerationItem: Identifiable, Equatable {
    enum Status: Equatable {
        case pending
        case inProgress
        case completed
        case failed(String)

        var iconName: String {
            switch self {
            case .pending:
                return "clock"
            case .inProgress:
                return "arrow.triangle.2.circlepath"
            case .completed:
                return "checkmark.circle"
            case .failed:
                return "exclamationmark.triangle"
            }
        }
    }

    struct VoiceSnapshot: Equatable {
        let id: String
        let name: String
    }

    let id: UUID
    let index: Int
    let text: String
    let provider: TTSProviderType
    let voice: VoiceSnapshot
    var status: Status

    init(index: Int,
         text: String,
         provider: TTSProviderType,
         voice: VoiceSnapshot,
         status: Status = .pending) {
        self.id = UUID()
        self.index = index
        self.text = text
        self.provider = provider
        self.voice = voice
        self.status = status
    }

    var previewText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "(Empty)" }
        if trimmed.count <= 80 {
            return trimmed
        }
        let prefix = trimmed.prefix(77)
        return "\(prefix)…"
    }
}
