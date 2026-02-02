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
    private(set) lazy var parakeetVocabularyService = ParakeetVocabularyService(modelContext: whisperState.modelContext)

    init(whisperState: WhisperState, modelsDirectory: URL) {
        self.whisperState = whisperState
        self.modelsDirectory = modelsDirectory
        parakeetTranscriptionService.vocabularyService = parakeetVocabularyService
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
        let service = service(for: model.provider)
        logger.debug("Transcribing with \(model.displayName) using \(String(describing: type(of: service)))")
        return try await service.transcribe(audioURL: audioURL, model: model)
    }

    func cleanup() {
        parakeetTranscriptionService.cleanup()
    }
}
