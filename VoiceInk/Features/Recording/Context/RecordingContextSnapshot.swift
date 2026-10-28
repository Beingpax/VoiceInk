import AppKit
import Foundation

struct RecordingContextSnapshot {
    var capturedAt = Date()
    var selectedText: String?
    var clipboardText: String?
    var screenText: String?
}

@MainActor
final class RecordingContextSnapshotStore {
    private(set) var snapshot = RecordingContextSnapshot()
    let vocabularyPreparation: RecordingVocabularyPreparation

    init(savedVocabulary: RecordingVocabulary) {
        vocabularyPreparation = RecordingVocabularyPreparation(savedVocabulary: savedVocabulary)
    }

    func updateSelectedText(_ text: String?) {
        snapshot.selectedText = Self.normalized(text)
    }

    func updateClipboardText(_ text: String?) {
        snapshot.clipboardText = Self.normalized(text)
    }

    func updateScreenText(_ text: String?) {
        snapshot.screenText = Self.normalized(text)
    }

    private static func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
enum RecordingContextCaptureService {
    static func startCapture(into store: RecordingContextSnapshotStore, language: String?) -> [Task<Void, Never>] {
        let screenCapture = Task { @MainActor in
            guard CGPreflightScreenCaptureAccess(), !Task.isCancelled else { return }
            let screenCaptureService = ScreenCaptureService()
            let screenText = await screenCaptureService.captureAndExtractText()
            guard !Task.isCancelled else { return }
            store.updateScreenText(screenText)
            if let text = store.snapshot.screenText {
                store.vocabularyPreparation.prepareScreenNames(in: text, language: language)
            }
        }
        return [
            Task { @MainActor in
                guard !Task.isCancelled else { return }
                let selectedText = await SelectedTextService.fetchSelectedText()
                guard !Task.isCancelled else { return }
                store.updateSelectedText(selectedText)
            },
            screenCapture,
        ]
    }
}
