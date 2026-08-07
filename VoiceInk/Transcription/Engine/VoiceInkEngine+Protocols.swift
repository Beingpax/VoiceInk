import Foundation

// MARK: - RecorderStateProvider

extension VoiceInkEngine: RecorderStateProvider {
    var contextSummary: RecorderContextSummary {
        guard let snapshot = activeRecordingContextSnapshot else { return .empty }
        return RecorderContextSummary(snapshot: snapshot)
    }

    /// Sends Cmd+Z to whatever now has focus. This leans on the target app's own undo stack, which
    /// is what makes it feel native — and also why it cannot be guaranteed.
    func undoResultPeek() async {
        _ = await CursorPaster.undoLastPaste()
        dismissResultPeek()
    }

    func retryResultPeek() {
        dismissResultPeek()
        LastTranscriptionService.retryLastTranscription(
            from: modelContext,
            transcriptionModelManager: transcriptionModelManager,
            serviceRegistry: serviceRegistry,
            enhancementService: enhancementService
        )
    }
}
