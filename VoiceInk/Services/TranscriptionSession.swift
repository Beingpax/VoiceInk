import Foundation
import os

/// Encapsulates a single recording-to-transcription lifecycle (streaming or file-based).
@MainActor
protocol TranscriptionSession: AnyObject {
    /// Prepares the session. Returns an audio chunk callback for streaming, or nil for file-based.
    func prepare(model: any TranscriptionModel) async throws -> ((Data) -> Void)?

    /// Called after recording stops. Returns the final transcribed text.
    func transcribe(audioURL: URL) async throws -> String

    /// Cancel the session and clean up resources.
    func cancel()
}

// MARK: - File-Based Session

/// File-based session: records to file, uploads after stop.
@MainActor
final class FileTranscriptionSession: TranscriptionSession {
    private let service: TranscriptionService
    private var model: (any TranscriptionModel)?

    init(service: TranscriptionService) {
        self.service = service
    }

    func prepare(model: any TranscriptionModel) async throws -> ((Data) -> Void)? {
        self.model = model
        return nil
    }

    func transcribe(audioURL: URL) async throws -> String {
        guard let model = model else {
            throw WhisperStateError.transcriptionFailed
        }
        return try await service.transcribe(audioURL: audioURL, model: model)
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
    // Batch-compatible override for streaming-only models rejected by the provider's REST API.
    private let fallbackModel: (any TranscriptionModel)?
    private var model: (any TranscriptionModel)?
    private var streamingFailed = false
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "StreamingTranscriptionSession")

    init(streamingService: StreamingTranscriptionService, fallbackService: TranscriptionService, fallbackModel: (any TranscriptionModel)? = nil) {
        self.streamingService = streamingService
        self.fallbackService = fallbackService
        self.fallbackModel = fallbackModel
    }

    func prepare(model: any TranscriptionModel) async throws -> ((Data) -> Void)? {
        self.model = model

        // Return callback immediately; WebSocket connects in background
        let service = streamingService
        let callback: (Data) -> Void = { [weak service] data in
            service?.sendAudioChunk(data)
        }

        Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                try await self.streamingService.startStreaming(model: model)
                await MainActor.run {
                    self.logger.notice("Streaming connected for \(model.displayName, privacy: .public)")
                }
            } catch {
                let desc = error.localizedDescription
                await MainActor.run {
                    self.logger.error("Failed to start streaming, will fall back to batch: \(desc, privacy: .public)")
                    self.streamingFailed = true
                }
            }
        }

        return callback
    }

    func transcribe(audioURL: URL) async throws -> String {
        guard let model = model else {
            throw WhisperStateError.transcriptionFailed
        }

        if !streamingFailed {
            do {
                let text = try await streamingService.stopAndGetFinalText()
                logger.notice("Streaming transcript received")
                return text
            } catch {
                logger.error("Streaming failed, falling back to batch: \(error.localizedDescription, privacy: .public)")
                streamingService.cancel()
            }
        } else {
            streamingService.cancel()
        }

        // Use fallbackModel if set — streaming-only models are rejected by the batch REST API.
        let modelForFallback = fallbackModel ?? model
        logger.notice("Using batch fallback for \(model.displayName, privacy: .public) with model \(modelForFallback.displayName, privacy: .public)")
        return try await fallbackService.transcribe(audioURL: audioURL, model: modelForFallback)
    }

    func cancel() {
        streamingService.cancel()
    }
}
