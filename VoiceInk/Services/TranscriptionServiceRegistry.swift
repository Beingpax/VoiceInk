import Foundation
import SwiftUI
import os

@MainActor
class TranscriptionServiceRegistry {
    private let whisperState: WhisperState
    private let modelsDirectory: URL
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "TranscriptionServiceRegistry")

    private(set) lazy var localTranscriptionService = LocalTranscriptionService(
        modelsDirectory: modelsDirectory,
        whisperState: whisperState
    )
    private(set) lazy var cloudTranscriptionService = CloudTranscriptionService(modelContext: whisperState.modelContext)
    private(set) lazy var nativeAppleTranscriptionService = NativeAppleTranscriptionService()
    private(set) lazy var parakeetTranscriptionService = ParakeetTranscriptionService()
    init(whisperState: WhisperState, modelsDirectory: URL) {
        self.whisperState = whisperState
        self.modelsDirectory = modelsDirectory
    }

    func service(for provider: ModelProvider) -> TranscriptionService {
        switch provider {
        case .local:
            return localTranscriptionService
        case .parakeet:
            return parakeetTranscriptionService
        case .nativeApple:
            return nativeAppleTranscriptionService
        default:
            return cloudTranscriptionService
        }
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let effectiveModel = batchFallbackModel(for: model) ?? model
        let service = service(for: effectiveModel.provider)
        logger.debug("Transcribing with \(effectiveModel.displayName, privacy: .public) using \(String(describing: type(of: service)), privacy: .public)")
        return try await service.transcribe(audioURL: audioURL, model: effectiveModel)
    }

    /// Creates a streaming or file-based session depending on the model's capabilities.
    func createSession(for model: any TranscriptionModel, onPartialTranscript: ((String) -> Void)? = nil) -> TranscriptionSession {
        if supportsStreaming(model: model) {
            let streamingService = StreamingTranscriptionService(
                modelContext: whisperState.modelContext,
                onPartialTranscript: onPartialTranscript
            )
            let fallback = service(for: model.provider)
            let fallbackModel = batchFallbackModel(for: model)
            return StreamingTranscriptionSession(streamingService: streamingService, fallbackService: fallback, fallbackModel: fallbackModel)
        } else {
            return FileTranscriptionSession(service: service(for: model.provider))
        }
    }

    // Maps streaming-only models to a batch-compatible equivalent for fallback.
    private func batchFallbackModel(for model: any TranscriptionModel) -> (any TranscriptionModel)? {
        switch (model.provider, model.name) {
        case (.mistral, "voxtral-mini-transcribe-realtime-2602"):
            return PredefinedModels.models.first { $0.name == "voxtral-mini-latest" }
        case (.soniox, "stt-rt-v4"):
            return PredefinedModels.models.first { $0.name == "stt-async-v4" }
        default:
            return nil
        }
    }

    /// Whether the given model supports streaming transcription
    private func supportsStreaming(model: any TranscriptionModel) -> Bool {
        switch model.provider {
        case .elevenLabs:
            return model.name == "scribe_v2"
        case .deepgram:
            return model.name == "nova-3" || model.name == "nova-3-medical"
        case .mistral:
            return model.name == "voxtral-mini-transcribe-realtime-2602"
        case .soniox:
            return model.name == "stt-rt-v4"
        default:
            return false
        }
    }

    func cleanup() {
        parakeetTranscriptionService.cleanup()
    }
}
