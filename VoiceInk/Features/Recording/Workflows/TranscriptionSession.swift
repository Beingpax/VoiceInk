import Foundation
import os

/// Encapsulates a single recording-to-transcription lifecycle (streaming or file-based).
@MainActor
protocol TranscriptionSession: AnyObject {
    /// Prepares the session. Returns an audio chunk callback for streaming, or nil for file-based.
    func prepare(
        configuration: TranscriptionRuntimeConfiguration,
        vocabulary: RecordingVocabulary
    ) async throws -> ((Data) -> Void)?

    /// Called after recording stops. Returns the final transcribed text.
    func transcribe(audioURL: URL, vocabulary: RecordingVocabulary) async throws -> String

    /// Cancel the session and clean up resources.
    func cancel()
}

// MARK: - File-Based Session

/// File-based session: records to file, uploads after stop.
@MainActor
final class FileTranscriptionSession: TranscriptionSession {
    private let service: TranscriptionService
    private var model: (any TranscriptionModel)?
    private var context: TranscriptionRequestContext = .currentDefaults

    init(service: TranscriptionService) {
        self.service = service
    }

    func prepare(
        configuration: TranscriptionRuntimeConfiguration,
        vocabulary: RecordingVocabulary
    ) async throws -> ((Data) -> Void)? {
        self.model = configuration.model
        self.context = configuration.requestContext.withVocabulary(vocabulary).scoped(to: configuration.model)
        return nil
    }

    func transcribe(audioURL: URL, vocabulary: RecordingVocabulary) async throws -> String {
        guard let model = model else {
            throw VoiceInkEngineError.transcriptionFailed
        }
        return try await service.transcribe(
            audioURL: audioURL, model: model, context: context.withVocabulary(vocabulary)
        )
    }

    func cancel() {
        // No-op for file-based transcription
    }
}

// MARK: - Streaming Session

/// Streaming session with automatic fallback to file-based upload on failure.
@MainActor
final class StreamingTranscriptionSession: TranscriptionSession {
    private let streamingService: StreamingTranscriptionService
    private let fallbackService: TranscriptionService
    private var model: (any TranscriptionModel)?
    private var context: TranscriptionRequestContext = .currentDefaults
    private var streamingFailed = false
    private var isCancelled = false
    private var startupTask: Task<Void, Never>?
    private var startupTaskID: UUID?
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "StreamingTranscriptionSession")

    init(streamingService: StreamingTranscriptionService, fallbackService: TranscriptionService) {
        self.streamingService = streamingService
        self.fallbackService = fallbackService
    }

    func prepare(
        configuration: TranscriptionRuntimeConfiguration,
        vocabulary: RecordingVocabulary
    ) async throws -> ((Data) -> Void)? {
        let model = configuration.model
        let context = configuration.requestContext.withVocabulary(vocabulary).scoped(to: model)

        self.model = model
        self.context = context
        logger.notice("Streaming session prepare model=\(model.displayName, privacy: .public)")

        // Start the provider in the background.
        let service = streamingService
        let callback: (Data) -> Void = { [weak service] data in
            service?.sendAudioChunk(data)
        }

        cancelStartup()
        let taskID = UUID()
        startupTaskID = taskID
        startupTask = Task { [weak self] in
            guard let self = self else { return }
            defer {
                if self.startupTaskID == taskID {
                    self.startupTask = nil
                    self.startupTaskID = nil
                }
            }
            guard !Task.isCancelled else { return }

            do {
                let start = Date()
                try await self.streamingService.startStreaming(model: model, context: context)
                guard !Task.isCancelled else {
                    self.streamingService.cancel()
                    return
                }
                self.logger.notice(
                    "Streaming session connected model=\(model.displayName, privacy: .public) elapsed=\(Date().timeIntervalSince(start), format: .fixed(precision: 3), privacy: .public)s"
                )
            } catch is CancellationError {
                self.streamingService.cancel()
            } catch {
                guard !Task.isCancelled else { return }
                let desc = error.localizedDescription
                self.logger.error("❌ Failed to start streaming, will fall back to batch: \(desc, privacy: .public)")
                self.streamingFailed = true
            }
        }

        return callback
    }

    func transcribe(audioURL: URL, vocabulary: RecordingVocabulary) async throws -> String {
        guard let model = model else {
            throw VoiceInkEngineError.transcriptionFailed
        }

        // Optional vocabulary never delays startup or finalization. Providers with a
        // batch endpoint can immediately fall back if the connection is not ready.
        let isUnified = model.provider == .fluidAudio
            && FluidAudioModelManager.isParakeetUnifiedModel(named: model.name)
        let requiresStreaming = CloudProviderRegistry.provider(for: model.provider)?.isStreamingOnly == true
        if isUnified || requiresStreaming {
            // These paths need their normal model/connection startup to produce any result.
            await startupTask?.value
        }
        try checkCancellation()
        if !isUnified, !requiresStreaming, !streamingService.isActive {
            streamingFailed = true
        }

        if !streamingFailed {
            do {
                let start = Date()
                logger.notice("Streaming stop/transcribe started model=\(model.displayName, privacy: .public)")
                let result = try await streamingService.stopAndFinalize()
                try checkCancellation()
                switch result {
                case .finalized(let text):
                    logger.notice(
                        "Streaming transcript received elapsed=\(Date().timeIntervalSince(start), format: .fixed(precision: 3), privacy: .public)s chars=\(text.count, privacy: .public)"
                    )
                    return text
                case .requiresBatchFallback:
                    logger.notice("Streaming provider requested full batch transcription")
                }
            } catch {
                if isCancelled || Task.isCancelled || error is CancellationError {
                    throw CancellationError()
                }
                logger.error("❌ Streaming failed, falling back to batch: \(error, privacy: .public)")
            }
        }

        stopStreaming()
        try checkCancellation()

        let fallbackStart = Date()
        logger.notice(
            "Using batch fallback for \(model.displayName, privacy: .public) file=\(audioURL.lastPathComponent, privacy: .public)"
        )
        let text = try await fallbackService.transcribe(
            audioURL: audioURL, model: model, context: context.withVocabulary(vocabulary)
        )
        logger.notice(
            "Batch fallback completed elapsed=\(Date().timeIntervalSince(fallbackStart), format: .fixed(precision: 3), privacy: .public)s chars=\(text.count, privacy: .public)"
        )
        return text
    }

    private func checkCancellation() throws {
        try Task.checkCancellation()
        guard !isCancelled else { throw CancellationError() }
    }

    func cancel() {
        isCancelled = true
        stopStreaming()
    }

    private func stopStreaming() {
        cancelStartup()
        streamingService.cancel()
    }

    private func cancelStartup() {
        startupTask?.cancel()
        startupTask = nil
        startupTaskID = nil
    }
}
