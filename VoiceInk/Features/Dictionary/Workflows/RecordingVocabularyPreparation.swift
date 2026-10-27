import Foundation

/// Builds optional screen vocabulary without delaying transcription or raw context capture.
@MainActor
final class RecordingVocabularyPreparation {
    private(set) var current: RecordingVocabulary
    private var preparationTask: Task<Void, Never>?
    private var isFinished = false

    init(savedVocabulary: RecordingVocabulary) {
        current = savedVocabulary
    }

    /// Called only after OCR completes. A finished run never starts new extraction.
    func prepareScreenNames(in text: String, language: String?) {
        guard !isFinished, preparationTask == nil else { return }
        let saved = current
        let extraction = Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled else { return saved }
            let names = RecordingVocabulary.screenNames(in: text, language: language)
            guard !Task.isCancelled else { return saved }
            return RecordingVocabulary(savedTerms: saved.terms, screenNames: names)
        }

        preparationTask = Task {
            let prepared = await withTaskCancellationHandler {
                await extraction.value
            } onCancel: {
                extraction.cancel()
            }
            guard !Task.isCancelled, !isFinished else { return }
            current = prepared
        }
    }

    /// Freeze whatever is ready and cancel unfinished work, without waiting for it.
    @discardableResult
    func finish() -> RecordingVocabulary {
        guard !isFinished else { return current }
        isFinished = true
        preparationTask?.cancel()
        preparationTask = nil
        return current
    }
}
