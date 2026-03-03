import Foundation
import SwiftData

/// Protocol that WhisperModelManager conforms to, decoupling TranscriptionServiceRegistry
/// and LocalTranscriptionService from concrete manager types.
@MainActor
protocol LocalModelProvider: AnyObject {
    var isModelLoaded: Bool { get }
    var whisperContext: WhisperContext? { get }
    var loadedLocalModel: WhisperModel? { get }
    var availableModels: [WhisperModel] { get }
}
