import Foundation
import os

@MainActor
final class TranscriptionDelivery {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "TranscriptionDelivery")

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

        if request.output.outputMode == .customCommand {
            await deliverCustomCommand(request, actions: actions)
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

    private func deliverCustomCommand(_ item: Request, actions: Actions) async {
        guard let text = item.text else {
            notifyCustomCommandFailure(CustomCommandDeliveryError.noTextToDeliver)
            SoundManager.shared.playStopSound()
            await actions.dismiss()
            return
        }

        guard let customCommand = item.output.customCommand,
              let command = customCommand.trimmedCommand else {
            notifyCustomCommandFailure(CustomCommandDeliveryError.commandNotConfigured)
            SoundManager.shared.playStopSound()
            await actions.dismiss()
            return
        }

        let commandText = deliverableText(from: text)
        SoundManager.shared.playStopSound()
        await actions.dismiss()

        Task {
            await runCustomCommand(command: command, commandText: commandText)
        }
    }

    private func runCustomCommand(command: String, commandText: String) async {
        do {
            let result = try await CustomCommandDeliveryRunner.run(
                command: command,
                timeout: 10,
                context: CustomCommandDeliveryContext(transcript: commandText)
            )

            if !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                logger.debug("Custom command stdout: \(result.stdout, privacy: .public)")
            }

            if !result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                logger.warning("Custom command stderr: \(result.stderr, privacy: .public)")
            }
        } catch {
            notifyCustomCommandFailure(error)
        }
    }

    private func notifyCustomCommandFailure(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        logger.error("Custom command failed: \(message, privacy: .public)")
        NotificationManager.shared.showNotification(
            title: String(format: String(localized: "Custom command failed: %@"), String(message.prefix(120))),
            type: .warning
        )
    }

    private func paste(_ text: String, output: OutputRuntimeConfiguration, actions: Actions) async {
        let textToPaste = deliverableText(from: text)
        let appendSpace = UserDefaults.standard.bool(forKey: "AppendTrailingSpace")
        let pastedText = textToPaste + (appendSpace ? " " : "")
        SoundManager.shared.playStopSound()
        await actions.dismiss()

        let pasteTask = CursorPaster.startPasteAtCursor(pastedText)

        let autoSendKey = output.outputMode == .paste ? output.autoSendKey : .none
        Task { @MainActor in
            _ = await pasteTask.value

            if autoSendKey.isEnabled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                CursorPaster.performAutoSend(autoSendKey)
            }
        }
    }

    private func deliverableText(from text: String) -> String {
        var textToDeliver = text
        if let restrictionMessage = LicenseViewModel().usageRestrictionMessage {
            textToDeliver = """
                \(restrictionMessage)
                \n\(textToDeliver)
                """
        }

        return textToDeliver
    }
}
