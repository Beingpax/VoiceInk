import Foundation
import AVFoundation
import FluidAudio
import os.log

class ParakeetStreamingTranscriptionService: TranscriptionService {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink.parakeet", category: "StreamingTranscription")
    private let lock = NSLock()

    private var streamingManager: StreamingAsrManager?
    private var isReady = false
    private var activeVersion: AsrModelVersion?
    private var loadError: Error?
    var vocabularyService: ParakeetVocabularyService?

    // Audio forwarding pipeline — preserves FIFO ordering from RT callback to StreamingAsrManager
    private var audioContinuation: AsyncStream<AudioChunk>.Continuation?
    private var audioForwardingTask: Task<Void, Never>?
    private var pendingStream: AsyncStream<AudioChunk>?

    // Voice activity detection
    private var vadProcessor: StreamingVadProcessor?

    private struct AudioChunk {
        let samples: [Float]
        let frameCount: UInt32
        let sampleRate: Double
        let channels: UInt32
    }

    private func version(for model: any TranscriptionModel) -> AsrModelVersion {
        model.name.lowercased().contains("v2") ? .v2 : .v3
    }

    /// Prepare the audio buffer before recording starts so feedAudio() can accept
    /// samples immediately, ensuring no audio is lost while the model loads.
    func prepareForStreaming() {
        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream()
        lock.withLock {
            audioContinuation = continuation
            isReady = true
            pendingStream = stream
        }
    }

    // MARK: - Model Loading

    private func loadStreamingManager(version: AsrModelVersion) async throws -> StreamingAsrManager {
        let isValid = try await AsrModels.isModelValid(version: version)
        if !isValid {
            throw ParakeetTranscriptionError.modelValidationFailed(
                "Parakeet models are corrupted. Please delete and re-download the model."
            )
        }

        let manager = StreamingAsrManager(config: .streaming)
        let models = try await AsrModels.loadFromCache(configuration: nil, version: version)

        // Configure vocabulary boosting before start(), per FluidAudio API
        await configureVocabularyBoosting(on: manager)

        try await manager.start(models: models, source: .microphone)

        return manager
    }

    // MARK: - Streaming Lifecycle

    func startStreaming(for model: ParakeetModel) async throws {
        let targetVersion = version(for: model)

        // Use pre-created buffer from prepareForStreaming() if available,
        // otherwise create one now (fallback for direct calls)
        let stream: AsyncStream<AudioChunk>
        if let prepared = lock.withLock({ () -> AsyncStream<AudioChunk>? in
            let s = pendingStream
            pendingStream = nil
            return s
        }) {
            stream = prepared
        } else {
            let (s, continuation) = AsyncStream<AudioChunk>.makeStream()
            lock.withLock {
                audioContinuation = continuation
                isReady = true
            }
            stream = s
        }

        // Load models (audio is being buffered in the AsyncStream meanwhile)
        do {
            let manager = try await loadStreamingManager(version: targetVersion)

            // Initialize VAD if enabled
            let vad = await StreamingVadProcessor.createIfEnabled(logger: logger)
            let useVAD = vad != nil

            lock.withLock { vadProcessor = vad }

            // Start forwarding task — drains all buffered audio first, then continues in real-time
            audioForwardingTask = Task {
                for await chunk in stream {
                    guard let buffer = Self.createPCMBuffer(from: chunk) else { continue }

                    if useVAD, let vad {
                        let isSpeech = await vad.isSpeech(
                            samples: chunk.samples,
                            sampleRate: chunk.sampleRate
                        )
                        guard isSpeech else { continue }
                    }

                    await manager.streamAudio(buffer)
                }
            }

            lock.withLock {
                streamingManager = manager
                activeVersion = targetVersion
                loadError = nil
            }

            logger.info("Streaming ASR started for \(targetVersion == .v2 ? "v2" : "v3")")
        } catch {
            // Model load failed — stop buffering and store error for transcribe() to throw
            let cont = lock.withLock { () -> AsyncStream<AudioChunk>.Continuation? in
                let c = audioContinuation
                audioContinuation = nil
                isReady = false
                loadError = error
                pendingStream = nil
                return c
            }
            cont?.finish()
            throw error
        }
    }

    // MARK: - Audio Feed (called from real-time audio thread)

    func feedAudio(_ samples: UnsafePointer<Float32>, frameCount: UInt32, sampleRate: Double, channels: UInt32) {
        let (ready, continuation) = lock.withLock { (isReady, audioContinuation) }

        guard ready, let continuation else { return }

        // Copy samples off the real-time thread and yield to ordered stream
        let count = Int(frameCount * channels)
        let copied = Array(UnsafeBufferPointer(start: samples, count: count))
        continuation.yield(AudioChunk(
            samples: copied,
            frameCount: frameCount,
            sampleRate: sampleRate,
            channels: channels
        ))
    }

    // MARK: - TranscriptionService

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let (error, manager, continuation) = lock.withLock { (loadError, streamingManager, audioContinuation) }

        if let error {
            cleanup()
            throw error
        }

        // If there's an active streaming session, finalize it
        if let manager {
            continuation?.finish()
            await audioForwardingTask?.value

            let result = try await manager.finish()

            lock.withLock {
                streamingManager = nil
                audioContinuation = nil
                audioForwardingTask = nil
                isReady = false
                activeVersion = nil
            }

            return result
        }

        // No active session — transcribe directly from file (e.g. retranscription from history)
        return try await transcribeFromFile(audioURL: audioURL, model: model)
    }

    private func transcribeFromFile(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let targetVersion = version(for: model)
        let manager = try await loadStreamingManager(version: targetVersion)
        let vad = await StreamingVadProcessor.createIfEnabled(logger: logger)
        let converter = AudioConverter()

        // Load audio file and feed it in chunks
        let audioFile = try AVAudioFile(forReading: audioURL)
        let format = audioFile.processingFormat
        let totalFrames = AVAudioFrameCount(audioFile.length)
        let samplesPerChunk = Int(StreamingAsrConfig.streaming.chunkSeconds * format.sampleRate)

        guard let fileBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
            throw ASRError.invalidAudioData
        }
        try audioFile.read(into: fileBuffer)

        var position = 0
        while position < Int(fileBuffer.frameLength) {
            let remaining = Int(fileBuffer.frameLength) - position
            let chunkSize = min(samplesPerChunk, remaining)

            guard let chunkBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunkSize)) else {
                break
            }
            chunkBuffer.frameLength = AVAudioFrameCount(chunkSize)

            for channel in 0..<Int(format.channelCount) {
                if let src = fileBuffer.floatChannelData?[channel],
                   let dst = chunkBuffer.floatChannelData?[channel] {
                    dst.update(from: src.advanced(by: position), count: chunkSize)
                }
            }

            if let vad {
                let mono = (try? converter.resampleBuffer(chunkBuffer)) ?? []
                if !mono.isEmpty {
                    let isSpeech = await vad.isSpeech(samples: mono, sampleRate: 16000)
                    guard isSpeech else {
                        position += chunkSize
                        continue
                    }
                }
            }

            await manager.streamAudio(chunkBuffer)
            position += chunkSize
        }

        return try await manager.finish()
    }

    // MARK: - Audio Buffer Conversion

    private static func createPCMBuffer(from chunk: AudioChunk) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: chunk.sampleRate,
            channels: AVAudioChannelCount(chunk.channels),
            interleaved: false
        ) else { return nil }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(chunk.frameCount)
        ) else { return nil }
        buffer.frameLength = AVAudioFrameCount(chunk.frameCount)

        if chunk.channels == 1 {
            if let channelData = buffer.floatChannelData?[0] {
                chunk.samples.withUnsafeBufferPointer { src in
                    channelData.update(from: src.baseAddress!, count: Int(chunk.frameCount))
                }
            }
        } else {
            for ch in 0..<Int(chunk.channels) {
                if let channelData = buffer.floatChannelData?[ch] {
                    for frame in 0..<Int(chunk.frameCount) {
                        channelData[frame] = chunk.samples[frame * Int(chunk.channels) + ch]
                    }
                }
            }
        }

        return buffer
    }

    // MARK: - Cleanup

    func cleanup() {
        let continuation = lock.withLock { () -> AsyncStream<AudioChunk>.Continuation? in
            let c = audioContinuation
            audioContinuation = nil
            streamingManager = nil
            audioForwardingTask?.cancel()
            audioForwardingTask = nil
            isReady = false
            activeVersion = nil
            loadError = nil
            vadProcessor = nil
            pendingStream = nil
            return c
        }
        continuation?.finish()
        vocabularyService?.cleanup()
    }

    // MARK: - Vocabulary Boosting

    private func configureVocabularyBoosting(on manager: StreamingAsrManager) async {
        guard let vocabularyService else { return }

        let ctcDirectory = CtcModels.defaultCacheDirectory(for: .ctc110m)
        guard CtcModels.modelsExist(at: ctcDirectory) else { return }

        let words = vocabularyService.fetchCurrentWords()
        guard !words.isEmpty else { return }

        do {
            let ctcModels = try await CtcModels.load(from: ctcDirectory)
            let tokenizer = try await CtcTokenizer.load(from: ctcDirectory)

            let terms = words.compactMap { word -> CustomVocabularyTerm? in
                let tokenIds = tokenizer.encode(word)
                guard !tokenIds.isEmpty else { return nil }
                return CustomVocabularyTerm(text: word, ctcTokenIds: tokenIds)
            }

            guard !terms.isEmpty else { return }

            let vocabulary = CustomVocabularyContext(terms: terms)
            try await manager.configureVocabularyBoosting(
                vocabulary: vocabulary,
                ctcModels: ctcModels
            )
            logger.info("Streaming vocabulary boosting configured with \(terms.count) terms")
        } catch {
            logger.notice("Streaming vocabulary boosting configuration failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Streaming VAD Processor

private class StreamingVadProcessor {
    private let vadManager: VadManager
    private let audioConverter: AudioConverter
    private let logger: Logger
    private var streamState: VadStreamState
    private var buffer: [Float] = []

    private init(vadManager: VadManager, streamState: VadStreamState, logger: Logger) {
        self.vadManager = vadManager
        self.audioConverter = AudioConverter()
        self.streamState = streamState
        self.logger = logger
    }

    static func createIfEnabled(logger: Logger) async -> StreamingVadProcessor? {
        guard UserDefaults.standard.bool(forKey: "IsVADEnabled") else { return nil }
        do {
            let vad = try await VadManager(config: VadConfig(defaultThreshold: 0.7))
            let state = await vad.makeStreamState()
            logger.info("Streaming VAD initialized")
            return StreamingVadProcessor(vadManager: vad, streamState: state, logger: logger)
        } catch {
            logger.notice("Streaming VAD init failed; proceeding without VAD: \(error.localizedDescription)")
            return nil
        }
    }

    /// Returns true if the audio contains speech, false if silence.
    /// Samples can be at any sample rate — they'll be resampled to 16kHz if needed.
    func isSpeech(samples: [Float], sampleRate: Double) async -> Bool {
        let samples16k: [Float]
        if sampleRate == 16000 {
            samples16k = samples
        } else {
            do {
                samples16k = try audioConverter.resample(samples, from: sampleRate)
            } catch {
                logger.notice("VAD resample failed; forwarding audio: \(error.localizedDescription)")
                return true
            }
        }

        buffer.append(contentsOf: samples16k)

        // Process in 4096-sample chunks (256ms at 16kHz, optimal for Silero VAD)
        while buffer.count >= 4096 {
            let chunk = Array(buffer.prefix(4096))
            buffer.removeFirst(4096)
            do {
                let result = try await vadManager.processStreamingChunk(chunk, state: streamState)
                streamState = result.state
            } catch {
                logger.notice("VAD processing failed; forwarding audio: \(error.localizedDescription)")
                return true
            }
        }

        return streamState.triggered
    }
}
