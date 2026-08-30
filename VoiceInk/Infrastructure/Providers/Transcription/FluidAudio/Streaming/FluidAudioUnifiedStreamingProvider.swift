import FluidAudio
import Foundation
import os

/// True streaming provider backed by FluidAudio's Parakeet Unified manager.
final class FluidAudioUnifiedStreamingProvider: StreamingTranscriptionProvider {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "FluidAudioUnifiedStreaming")
    private var manager: StreamingUnifiedAsrManager?
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
        let manager = StreamingUnifiedAsrManager(
            config: FluidAudioModelManager.parakeetUnifiedStreamingConfig,
            encoderPrecision: FluidAudioModelManager.parakeetUnifiedPrecision
        )
        let continuation = eventsContinuation
        await manager.setPartialTranscriptCallback { partial in
            continuation?.yield(.partial(text: partial))
        }
        try await manager.loadModels(from: FluidAudioModelManager.parakeetUnifiedCacheDirectory())
        self.manager = manager
        eventsContinuation?.yield(.sessionStarted)
        logger.notice("Parakeet Unified streaming started for \(model.displayName, privacy: .public)")
    }

    func sendAudioChunk(_ data: Data) async throws {
        guard let manager else {
            throw StreamingTranscriptionError.notConnected
        }

        guard !data.isEmpty else { return }

        guard let buffer = PCMAudioConverter.pcmBuffer(fromPCM16Data: data) else {
            throw StreamingTranscriptionError.audioConversionFailed
        }

        try await manager.appendAudio(buffer)
        try await manager.processBufferedAudio()
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
        logger.notice("Parakeet Unified streaming disconnected")
    }
}
