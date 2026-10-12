import Foundation
import LLMkit
import SwiftData

@MainActor
final class AssistantChatService {
    struct Reply {
        let text: String
        let duration: TimeInterval
        let systemPrompt: String?
        let requestLog: String
    }

    private let modelContext: ModelContext
    private let aiService: AIService

    private var requestTimeout: TimeInterval {
        EnhancementRequestSettings.timeout
    }

    init(modelContext: ModelContext, aiService: AIService) {
        self.modelContext = modelContext
        self.aiService = aiService
    }

    func requestAssistantReply(
        provider: AIProvider,
        modelName: String?,
        systemPrompt: String?,
        messages: [AssistantDisplayMessage]
    ) async throws -> Reply {
        let chatMessages = messages.map { message in
            switch message.role {
            case .user:
                return ChatMessage.user(message.content)
            case .assistant:
                return ChatMessage.assistant(message.content)
            }
        }

        let startTime = Date()
        let text = try await requestReplyWithTimeoutPolicy(
            provider: provider,
            modelName: modelName,
            messages: chatMessages,
            systemPrompt: systemPrompt
        )

        return Reply(
            text: text,
            duration: Date().timeIntervalSince(startTime),
            systemPrompt: systemPrompt,
            requestLog: Self.requestLog(from: messages)
        )
    }

    private func requestReplyWithTimeoutPolicy(
        provider: AIProvider,
        modelName: String?,
        messages: [ChatMessage],
        systemPrompt: String?
    ) async throws -> String {
        let maximumAttempts = EnhancementRequestSettings.retryOnTimeout
            ? EnhancementRequestSettings.maximumAttempts
            : 1

        var attempt = 0
        while attempt < maximumAttempts {
            do {
                return try await aiService.completeChat(
                    provider: provider,
                    modelName: modelName,
                    messages: messages,
                    systemPrompt: systemPrompt,
                    timeout: requestTimeout
                )
            } catch {
                attempt += 1
                guard Self.isTimeout(error), attempt < maximumAttempts else {
                    throw error
                }
            }
        }

        throw EnhancementError.timeout
    }

    private static func isTimeout(_ error: Error) -> Bool {
        if let llmKitError = error as? LLMKitError {
            switch llmKitError {
            case .timeout:
                return true
            case .httpError(let statusCode, _):
                return statusCode == 408
            default:
                break
            }
        }
        if let enhancementError = error as? EnhancementError, case .timeout = enhancementError {
            return true
        }
        if let localError = error as? LocalAIError, case .timeout = localError {
            return true
        }
        if let localCLIError = error as? LocalCLIError, case .timeout = localCLIError {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut
    }

    func applyAssistantTurn(
        transcription: Transcription,
        response: Reply,
        provider: AIProvider,
        modelName: String?,
        promptName: String?
    ) {
        transcription.enhancedText = response.text
        transcription.aiEnhancementModelName = modelName ?? provider.defaultModel
        transcription.promptName = promptName
        transcription.enhancementDuration = response.duration
        transcription.aiRequestSystemMessage = response.systemPrompt
        transcription.aiRequestUserMessage = response.requestLog
        transcription.transcriptionStatus = TranscriptionStatus.completed.rawValue
    }

    func saveTypedAssistantTurn(
        input: String,
        response: Reply,
        provider: AIProvider,
        modelName: String?,
        promptName: String?,
        modeName: String?,
        modeEmoji: String?
    ) throws {
        let transcription = Transcription(
            text: input,
            duration: 0,
            enhancedText: response.text,
            aiEnhancementModelName: modelName ?? provider.defaultModel,
            promptName: promptName,
            enhancementDuration: response.duration,
            aiRequestSystemMessage: response.systemPrompt,
            aiRequestUserMessage: response.requestLog,
            modeName: modeName,
            modeEmoji: modeEmoji,
            transcriptionStatus: .completed
        )

        modelContext.insert(transcription)
        try modelContext.save()
        NotificationCenter.default.post(name: .transcriptionCreated, object: transcription)
        NotificationCenter.default.post(name: .transcriptionCompleted, object: transcription)
    }

    private static func requestLog(from messages: [AssistantDisplayMessage]) -> String {
        messages.map { message in
            let label: String
            switch message.role {
            case .assistant:
                label = "Assistant"
            case .user:
                label = "User"
            }
            return "\(label):\n\(message.content)"
        }
        .joined(separator: "\n\n")
    }
}
