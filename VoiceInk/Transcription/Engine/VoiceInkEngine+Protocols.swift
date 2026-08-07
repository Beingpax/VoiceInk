import Foundation

// MARK: - RecorderStateProvider

extension VoiceInkEngine: RecorderStateProvider {
    var contextSummary: RecorderContextSummary {
        guard let snapshot = activeRecordingContextSnapshot else { return .empty }
        return RecorderContextSummary(snapshot: snapshot)
    }
}
