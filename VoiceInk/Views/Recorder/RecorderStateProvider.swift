import Foundation

// Protocol for objects that provide live recorder state to the UI.
@MainActor
protocol RecorderStateProvider: AnyObject {
    var recordingState: RecordingState { get }
    var partialTranscript: String { get }
    /// What will be sent alongside the audio. Captured per take by the engine; previously
    /// invisible to the user.
    var contextSummary: RecorderContextSummary { get }
}
