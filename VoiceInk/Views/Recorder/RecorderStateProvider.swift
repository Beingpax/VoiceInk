import Foundation

// Protocol for objects that provide live recorder state to the UI.
@MainActor
protocol RecorderStateProvider: AnyObject {
    var recordingState: RecordingState { get }
    var partialTranscript: String { get }
    /// What will be sent alongside the audio. Captured per take by the engine; previously
    /// invisible to the user.
    var contextSummary: RecorderContextSummary { get }
    /// Set for a few seconds after delivery so a bad take can be undone or retried.
    var resultPeek: RecorderResultPeek? { get }
    /// Length of the take now being processed, and the model doing it — enough to predict the
    /// wait from that model's recorded history.
    var lastTakeAudioDuration: TimeInterval { get }
    var activeTranscriptionModelName: String? { get }

    /// Result peek actions. On the provider rather than threaded as callbacks, so the window
    /// managers stay unaware of the peek entirely.
    func undoResultPeek() async
    func retryResultPeek()
    func dismissResultPeek()
    func setResultPeekHovered(_ isHovered: Bool)
}
