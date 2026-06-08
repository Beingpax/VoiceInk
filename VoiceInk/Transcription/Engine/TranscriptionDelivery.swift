import Foundation

@MainActor
final class TranscriptionDelivery {
    struct Request {
        let transcription: Transcription
        let text: String?
        let output: OutputRuntimeConfiguration
        let responseConfig: EnhancementRuntimeConfiguration?
        let responseError: String?
        let isAssistantFollowUp: Bool
    }

    struct Actions {
        let setState: (RecordingState) -> Void
        let dismiss: () async -> Void
        let sendFollowUp: (String, Transcription) async -> Void
        let showResponse: (String, String?) async -> Void
        let failResponse: (String) async -> Void
    }

    func deliver(_ request: Request, actions: Actions) async {
        guard request.transcription.transcriptionStatus == TranscriptionStatus.completed.rawValue else {
            await actions.dismiss()
            return
        }

        if request.isAssistantFollowUp {
            await deliverFollowUp(request, actions: actions)
            return
        }

        if request.output.outputMode == .respond,
           request.responseConfig != nil || request.responseError != nil {
            await deliverResponse(request, actions: actions)
            return
        }

        if let text = request.text {
            await paste(text, output: request.output, actions: actions)
        } else {
            await actions.dismiss()
        }
    }

    private func deliverFollowUp(_ item: Request, actions: Actions) async {
        SoundManager.shared.playStopSound()

        guard let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return
        }

        actions.setState(.enhancing)
        await actions.sendFollowUp(text, item.transcription)
    }

    private func deliverResponse(_ item: Request, actions: Actions) async {
        SoundManager.shared.playStopSound()

        if let responseError = item.responseError {
            await actions.failResponse("Enhancement failed: \(responseError)")
        } else if let text = item.text,
                  item.responseConfig != nil {
            await actions.showResponse(text, item.transcription.aiRequestSystemMessage)
        } else {
            await actions.failResponse("No response was generated.")
        }
    }

    private func paste(_ text: String, output: OutputRuntimeConfiguration, actions: Actions) async {
        var textToPaste = text
        if let restrictionMessage = LicenseViewModel().usageRestrictionMessage {
            textToPaste = """
                \(restrictionMessage)
                \n\(textToPaste)
                """
        }

        let appendSpace = UserDefaults.standard.bool(forKey: "AppendTrailingSpace")
        let pastedText = textToPaste + (appendSpace ? " " : "")
        _ = await CursorPaster.startPasteAtCursor(pastedText).value
        SoundManager.shared.playStopSound()

        let autoSendKey = output.outputMode == .paste ? output.autoSendKey : .none
        if autoSendKey.isEnabled {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                CursorPaster.performAutoSend(autoSendKey)
            }
        }

        await actions.dismiss()
    }
}
