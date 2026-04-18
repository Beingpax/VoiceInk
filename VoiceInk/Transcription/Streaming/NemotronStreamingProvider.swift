import AVFoundation
import FluidAudio
import Foundation
import os

/// Wraps FluidAudio's StreamingNemotronAsrManager as a VoiceInk StreamingTranscriptionProvider.
/// Partial updates are yielded on every processed chunk; the final transcript is yielded
/// as `.committed(text:)` in response to `commit()`.
final class NemotronStreamingProvider: StreamingTranscriptionProvider {

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "NemotronStreaming")

    private(set) var transcriptionEvents: AsyncStream<StreamingTranscriptionEvent>
    private var eventsContinuation: AsyncStream<StreamingTranscriptionEvent>.Continuation?

    private let manager: StreamingNemotronAsrManager
    private let chunkSizeMs: Int
    private let sampleRate: Double = 16000.0

    /// Initialise with a pre-resolved chunk size so the caller (which IS on the
    /// main actor when it reads `modelManager.nemotronChunkSize`) can pass the
    /// value in without actor-isolation issues.
    init(chunkSize: NemotronChunkSize) {
        self.chunkSizeMs = chunkSize.rawValue
        self.manager = StreamingNemotronAsrManager(requestedChunkSize: chunkSize)

        var continuation: AsyncStream<StreamingTranscriptionEvent>.Continuation!
        transcriptionEvents = AsyncStream { continuation = $0 }
        eventsContinuation = continuation
    }

    deinit {
        eventsContinuation?.finish()
    }

    func connect(model: any TranscriptionModel, language: String?) async throws {
        // Wire partial-transcript callback before loading so early chunks aren't missed.
        let cont = eventsContinuation
        await manager.setPartialCallback { text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                cont?.yield(.partial(text: trimmed))
            }
        }

        try await manager.loadModels(to: nil, configuration: nil, progressHandler: nil)
        await manager.reset()
        eventsContinuation?.yield(.sessionStarted)
        logger.notice("Nemotron streaming started (\(self.chunkSizeMs)ms chunks)")
    }

    func sendAudioChunk(_ data: Data) async throws {
        guard let pcm = Self.makePCMBuffer(from: data, sampleRate: sampleRate) else { return }
        do {
            _ = try await manager.process(audioBuffer: pcm)
        } catch {
            logger.error("Nemotron process failed: \(error.localizedDescription, privacy: .public)")
            eventsContinuation?.yield(.error(error))
        }
    }

    func commit() async throws {
        let finalText = (try? await manager.finish()) ?? ""
        let normalized = TextNormalizer.shared.normalizeSentence(finalText)
        eventsContinuation?.yield(.committed(text: normalized))
    }

    func disconnect() async {
        await manager.reset()
        await manager.cleanup()
        eventsContinuation?.finish()
        logger.notice("Nemotron streaming disconnected")
    }

    // MARK: - Helpers

    /// Convert raw PCM-16 little-endian data to a 16 kHz mono Float32 AVAudioPCMBuffer.
    private static func makePCMBuffer(from data: Data, sampleRate: Double) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else { return nil }

        let sampleCount = data.count / MemoryLayout<Int16>.size
        guard sampleCount > 0 else { return nil }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(sampleCount)
        ) else { return nil }

        buffer.frameLength = AVAudioFrameCount(sampleCount)
        if let channel = buffer.floatChannelData?[0] {
            data.withUnsafeBytes { rawPtr in
                let int16Ptr = rawPtr.bindMemory(to: Int16.self)
                for i in 0..<sampleCount {
                    channel[i] = Float(int16Ptr[i]) / 32767.0
                }
            }
        }
        return buffer
    }
}
