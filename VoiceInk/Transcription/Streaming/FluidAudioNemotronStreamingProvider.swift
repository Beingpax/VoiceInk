import FluidAudio
import Foundation
import os

/// True streaming provider backed by FluidAudio's Nemotron multilingual manager.
final class FluidAudioNemotronStreamingProvider: StreamingTranscriptionProvider {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "FluidAudioNemotronStreaming")
    private var manager: StreamingNemotronMultilingualAsrManager?
    private var eventsContinuation: AsyncStream<StreamingTranscriptionEvent>.Continuation?

    private(set) var transcriptionEvents: AsyncStream<StreamingTranscriptionEvent>

    init() {
        var continuation: AsyncStream<StreamingTranscriptionEvent>.Continuation!
        transcriptionEvents = AsyncStream { continuation = $0 }
        eventsContinuation = continuation
    }

    deinit {
        eventsContinuation?.finish()
    }

    func connect(model: any TranscriptionModel, language: String?) async throws {
        let cacheDirectory = FluidAudioModelManager.nemotronCacheDirectory(for: model.name)
        let manager = StreamingNemotronMultilingualAsrManager()
        let continuation = eventsContinuation

        await manager.setPartialCallback { partial in
            continuation?.yield(.partial(text: partial))
        }
        try await manager.loadModels(from: cacheDirectory)
        let compatibleLanguage = TranscriptionLanguageSupport.validLanguageOrFallback(
            language,
            for: model
        )
        await manager.setLanguage(FluidAudioModelManager.nemotronLanguageHint(from: compatibleLanguage))

        self.manager = manager
        eventsContinuation?.yield(.sessionStarted)
        logger.notice("Nemotron streaming started for \(model.displayName, privacy: .public)")
    }

    func sendAudioChunk(_ data: Data) async throws {
        guard let manager else {
            throw StreamingTranscriptionError.notConnected
        }

        let samples = PCMAudioConverter.float32Samples(fromPCM16Data: data)
        guard !samples.isEmpty else { return }

        _ = try await manager.process(samples: samples)
    }

    func commit() async throws {
        guard let manager else {
            throw StreamingTranscriptionError.notConnected
        }

        let finalText = try await manager.finish()
        let text = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = TextNormalizer.shared.normalizeSentence(text)
        eventsContinuation?.yield(.committed(text: normalized))
    }

    func disconnect() async {
        await manager?.cleanup()
        manager = nil
        eventsContinuation?.finish()
        logger.notice("Nemotron streaming disconnected")
    }
}
