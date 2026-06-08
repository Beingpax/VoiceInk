import Foundation

@MainActor
extension VoiceInkEngine {
    func sendAssistantFollowUp(_ text: String, transcription: Transcription? = nil) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let assistantChat,
              let provider = assistantSession.provider else {
            return
        }

        let modelName = assistantSession.modelName
        let modeName = assistantSession.modeName
        let modeEmoji = assistantSession.modeEmoji
        let promptName = assistantSession.promptName
        let systemPrompt = assistantSession.systemPrompt
        let userMessage = assistantSession.beginFollowUp(trimmed)

        do {
            let reply = try await assistantChat.requestAssistantReply(
                provider: provider,
                modelName: modelName,
                systemPrompt: systemPrompt,
                messages: assistantSession.messages
            )

            guard assistantSession.hasMessage(id: userMessage.id),
                  assistantSession.provider == provider else {
                return
            }

            assistantSession.finishFollowUp(reply.text)

            do {
                if let transcription {
                    assistantChat.applyAssistantTurn(
                        transcription: transcription,
                        response: reply,
                        provider: provider,
                        modelName: modelName,
                        promptName: promptName
                    )
                } else {
                    try assistantChat.saveTypedAssistantTurn(
                        input: trimmed,
                        response: reply,
                        provider: provider,
                        modelName: modelName,
                        promptName: promptName,
                        modeName: modeName,
                        modeEmoji: modeEmoji
                    )
                }
            } catch {
                let errorDescription = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                NotificationManager.shared.showNotification(
                    title: "Assistant response was not saved: \(String(errorDescription.prefix(80)))",
                    type: .warning
                )
            }
        } catch {
            guard assistantSession.hasMessage(id: userMessage.id),
                  assistantSession.provider == provider else {
                return
            }
            let errorDescription = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            assistantSession.fail(errorDescription)
        }
    }

    func completeAssistantResponse(
        _ response: String,
        systemPrompt: String?
    ) async {
        assistantSession.finishInitialResponse(response, systemPrompt: systemPrompt)
    }
}
