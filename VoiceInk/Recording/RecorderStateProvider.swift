import Foundation

/// Protocol for objects that can serve as the recorder's state source.
/// VoiceInkEngine conforms to this protocol.
@MainActor
protocol RecorderStateProvider: AnyObject {
    var recordingState: RecordingState { get }
    var partialTranscript: String { get }
    var enhancementService: AIEnhancementService? { get }
}
