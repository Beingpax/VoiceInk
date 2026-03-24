import Foundation
import LLMkit

enum ConversationRole: String, Codable {
    case user
    case assistant
}

struct ConversationMessage: Identifiable {
    let id = UUID()
    let role: ConversationRole
    let content: String
    let timestamp: Date
}

@MainActor
class ConversationHistory: ObservableObject {
    @Published var messages: [ConversationMessage] = []
    let maxTurns: Int

    init(maxTurns: Int = 10) {
        self.maxTurns = maxTurns
    }

    func append(role: ConversationRole, content: String) {
        messages.append(ConversationMessage(role: role, content: content, timestamp: Date()))
        // Trim to maxTurns, preserving complete user/assistant pairs
        let maxMessages = maxTurns * 2
        if messages.count > maxMessages {
            var trimmed = Array(messages.suffix(maxMessages))
            // Ensure first message is from user (don't start with orphaned assistant)
            while let first = trimmed.first, first.role == .assistant, trimmed.count > 1 {
                trimmed.removeFirst()
            }
            messages = trimmed
        }
    }

    func clear() {
        messages.removeAll()
    }

    func asLLMMessages() -> [ChatMessage] {
        messages.map { msg in
            switch msg.role {
            case .user:
                return .user(msg.content)
            case .assistant:
                return .assistant(msg.content)
            }
        }
    }
}
