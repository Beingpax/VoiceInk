import AppKit
import Foundation

// MARK: - RecorderStateProvider

extension VoiceInkEngine: RecorderStateProvider {
    var lastTakeAudioDuration: TimeInterval {
        LastTranscriptionService.getLastTranscription(from: modelContext)?.duration ?? 0
    }

    var activeTranscriptionModelName: String? {
        ModeRuntimeResolver.transcriptionConfiguration(
            transcriptionModelManager: transcriptionModelManager
        )?.model.name
    }

    /// Stops and processes the take, as if the shortcut had been pressed again.
    func stopTakeFromPanel() async {
        await recorderUIManager?.toggleRecorderPanel(modeId: nil)
    }

    /// Discards the take entirely.
    func cancelTakeFromPanel() async {
        await cancelRecording()
    }

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

    /// Re-runs the AI enhancement over the same transcript and replaces what was pasted.
    ///
    /// Re-transcribing was the obvious reading of "retry" and the wrong one: the same audio through
    /// the same model returns the same words, so the button appeared to do nothing. Enhancement is
    /// the step that can actually produce a different — and usually better — result, because the
    /// model samples afresh each time.
    func retryResultPeek() {
        guard resultPeek != nil else { return }
        dismissResultPeek()

        Task { @MainActor in
            guard let last = LastTranscriptionService.getLastTranscription(from: modelContext) else {
                NotificationManager.shared.showNotification(
                    title: String(localized: "Nothing to retry"), type: .error)
                return
            }

            guard let enhancementService,
                let aiService = enhancementService.getAIService()
            else {
                NotificationManager.shared.showNotification(
                    title: String(localized: "Enable AI enhancement on this mode to retry"),
                    type: .info
                )
                return
            }

            let configuration = ModeRuntimeResolver.currentEnhancementConfiguration(
                mode: ModeManager.shared.currentEffectiveConfiguration,
                enhancementService: enhancementService,
                aiService: aiService
            )

            guard configuration.isEnabled else {
                NotificationManager.shared.showNotification(
                    title: String(localized: "Enable AI enhancement on this mode to retry"),
                    type: .info
                )
                return
            }

            do {
                let result = try await enhancementService.enhance(
                    last.text,
                    configuration: configuration,
                    contextSnapshot: activeRecordingContextSnapshot
                )

                let enhanced = result.text
                guard !enhanced.isEmpty else {
                    NotificationManager.shared.showNotification(
                        title: String(localized: "Retry produced no text"), type: .error)
                    return
                }

                last.enhancedText = enhanced
                try? modelContext.save()

                // Replace rather than append: undo the first result, then paste the new one.
                _ = await CursorPaster.undoLastPaste()
                try? await Task.sleep(for: .milliseconds(120))
                _ = await CursorPaster.startPasteAtCursor(enhanced).value
            } catch {
                NotificationManager.shared.showNotification(
                    title: String(localized: "Retry failed"), type: .error)
            }
        }
    }

}
