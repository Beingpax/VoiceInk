import Foundation
import Combine

enum AssistantMessageRole: String, Codable {
    case user
    case assistant
}

struct AssistantDisplayMessage: Identifiable, Equatable {
    let id: UUID
    let role: AssistantMessageRole
    let content: String
    let createdAt: Date
}

enum AssistantPhase: Equatable {
    case inactive
    case responding
    case ready
    case sendingFollowUp
    case failed(String)
}

@MainActor
final class AssistantSession: ObservableObject {
    @Published private(set) var phase: AssistantPhase = .inactive
    @Published private(set) var messages: [AssistantDisplayMessage] = []

    private(set) var provider: AIProvider?
    private(set) var modelName: String?
    private(set) var modeName: String?
    private(set) var modeEmoji: String?
    private(set) var promptName: String?
    private(set) var systemPrompt: String?

    var isVisible: Bool {
        phase != .inactive
    }

    var isBusy: Bool {
        phase == .responding || phase == .sendingFollowUp
    }

    var canSendFollowUp: Bool {
        provider != nil && !messages.isEmpty && !isBusy
    }

    func beginInitialResponse(
        transcript: String,
        provider: AIProvider?,
        modelName: String?,
        modeName: String?,
        modeEmoji: String?,
        promptName: String?
    ) {
        self.provider = provider
        self.modelName = modelName
        self.modeName = modeName
        self.modeEmoji = modeEmoji
        self.promptName = promptName
        messages = []

        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTranscript.isEmpty {
            messages.append(
                AssistantDisplayMessage(
                    id: UUID(),
                    role: .user,
                    content: trimmedTranscript,
                    createdAt: Date()
                )
            )
        }

        phase = .responding
    }

    func finishInitialResponse(_ response: String, systemPrompt: String?) {
        self.systemPrompt = systemPrompt

        let trimmedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedResponse.isEmpty {
            appendOrReplace(
                message: AssistantDisplayMessage(
                    id: UUID(),
                    role: .assistant,
                    content: trimmedResponse,
                    createdAt: Date()
                )
            )
        }
        phase = .ready
    }

    @discardableResult
    func beginFollowUp(_ text: String) -> AssistantDisplayMessage {
        let userMessage = AssistantDisplayMessage(
            id: UUID(),
            role: .user,
            content: text,
            createdAt: Date()
        )
        appendOrReplace(message: userMessage)
        phase = .sendingFollowUp
        return userMessage
    }

    @discardableResult
    func finishFollowUp(_ text: String) -> AssistantDisplayMessage {
        let assistantMessage = AssistantDisplayMessage(
            id: UUID(),
            role: .assistant,
            content: text,
            createdAt: Date()
        )
        appendOrReplace(message: assistantMessage)
        phase = .ready
        return assistantMessage
    }

    func hasMessage(id: UUID) -> Bool {
        messages.contains { $0.id == id }
    }

    func fail(_ message: String) {
        phase = .failed(message)
    }

    func reset() {
        phase = .inactive
        messages = []
        provider = nil
        modelName = nil
        modeName = nil
        modeEmoji = nil
        promptName = nil
        systemPrompt = nil
    }

    private func appendOrReplace(message: AssistantDisplayMessage) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
        } else {
            messages.append(message)
        }
    }
}
