import AppKit
import Foundation

// MARK: - RecorderStateProvider

extension VoiceInkEngine: RecorderStateProvider {
    var contextSummary: RecorderContextSummary {
        guard let snapshot = activeRecordingContextSnapshot else { return .empty }
        return RecorderContextSummary(snapshot: snapshot)
    }

    /// Sends Cmd+Z to the app the text landed in. Leaning on that app's own undo stack is what
    /// makes it feel native, and also why it cannot be guaranteed — an app without undo support,
    /// or one typed into since, will not restore cleanly.
    func undoResultPeek() async {
        dismissResultPeek()
        _ = await CursorPaster.undoLastPaste()
    }

    /// Re-transcribes the same audio and pastes the new result.
    ///
    /// Deliberately not `LastTranscriptionService.retryLastTranscription`, which only copies to the
    /// clipboard — correct for a keyboard shortcut fired from anywhere, wrong for a button on a
    /// peek that is sitting next to text the user expects to be replaced.
    func retryResultPeek() {
        guard resultPeek != nil else { return }
        dismissResultPeek()

        Task { @MainActor in
            guard let audioURLString = LastTranscriptionService
                .getLastTranscription(from: modelContext)?.audioFileURL,
                let audioURL = URL(string: audioURLString),
                FileManager.default.fileExists(atPath: audioURL.path)
            else {
                NotificationManager.shared.showNotification(
                    title: String(localized: "Cannot retry: audio file not found"),
                    type: .error
                )
                return
            }

            guard let configuration = ModeRuntimeResolver.transcriptionConfiguration(
                transcriptionModelManager: transcriptionModelManager
            ) else {
                NotificationManager.shared.showNotification(
                    title: String(localized: "No transcription model selected"),
                    type: .error
                )
                return
            }

            let service = AudioTranscriptionService(
                modelContext: modelContext,
                serviceRegistry: serviceRegistry,
                enhancementService: enhancementService
            )

            do {
                let result = try await service.retranscribeAudio(
                    from: audioURL, using: configuration.model)
                let retried = result.transcription
                let text =
                    result.enhancementFailure == nil && retried.enhancedText?.isEmpty == false
                    ? retried.enhancedText! : retried.text

                // Remove the first result before inserting the new one, otherwise retry appends
                // and you end up with the sentence twice.
                _ = await CursorPaster.undoLastPaste()
                try? await Task.sleep(for: .milliseconds(120))
                _ = await CursorPaster.startPasteAtCursor(text).value
            } catch {
                NotificationManager.shared.showNotification(
                    title: String(localized: "Retry failed"),
                    type: .error
                )
            }
        }
    }

}
