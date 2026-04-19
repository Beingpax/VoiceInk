import Foundation
import SwiftUI
import SwiftData
import os

@MainActor
class TranscriptionServiceRegistry {
    private weak var modelProvider: (any LocalModelProvider)?
    private let modelsDirectory: URL
    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "TranscriptionServiceRegistry")

    private(set) lazy var localTranscriptionService = LocalTranscriptionService(
        modelsDirectory: modelsDirectory,
        modelProvider: modelProvider
    )
    private(set) lazy var cloudTranscriptionService = CloudTranscriptionService(modelContext: modelContext)
    private(set) lazy var nativeAppleTranscriptionService = NativeAppleTranscriptionService()
    private(set) lazy var fluidAudioTranscriptionService = FluidAudioTranscriptionService()

    init(
        modelProvider: any LocalModelProvider,
        modelsDirectory: URL,
        modelContext: ModelContext
    ) {
        self.modelProvider = modelProvider
        self.modelsDirectory = modelsDirectory
        self.modelContext = modelContext
    }

    func service(for provider: ModelProvider) -> TranscriptionService {
        switch provider {
        case .local:
            return localTranscriptionService
        case .fluidAudio:
            return fluidAudioTranscriptionService
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
                modelContext: modelContext,
                fluidAudioService: model.provider == .fluidAudio ? fluidAudioTranscriptionService : nil,
                onPartialTranscript: onPartialTranscript
            )
            let fallback = service(for: model.provider)
            let fallbackModel = batchFallbackModel(for: model)
            return StreamingTranscriptionSession(streamingService: streamingService, fallbackService: fallback, fallbackModel: fallbackModel)
        } else {
            return FileTranscriptionSession(service: service(for: model.provider))
        }
    }

    /// Returns the model that would actually be used for batch/file transcription.
    /// For streaming-only models with a batch fallback (e.g. Soniox stt-rt-v4 → stt-async-v4),
    /// this returns the fallback; otherwise returns `model` itself.
    ///
    /// Callers that persist transcription metadata should record this model's
    /// displayName, not the originally-selected model's, so the record accurately
    /// reflects which engine produced the text.
    func effectiveBatchModel(for model: any TranscriptionModel) -> any TranscriptionModel {
        return batchFallbackModel(for: model) ?? model
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
        case .speechmatics:
            return model.name == "speechmatics-enhanced"
        case .fluidAudio:
            return UserDefaults.standard.object(forKey: "parakeet-streaming-enabled") as? Bool ?? true
        default:
            return false
        }
    }

    func cleanup() async {
        await fluidAudioTranscriptionService.cleanup()
    }
}
