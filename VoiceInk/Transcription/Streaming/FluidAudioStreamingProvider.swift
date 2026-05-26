import FluidAudio
import Foundation
import os

/// Agreement-based on-device streaming transcription using FluidAudio ASR.
final class FluidAudioStreamingProvider: StreamingTranscriptionProvider {

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "FluidAudioStreaming")
    private let fluidAudioService: FluidAudioTranscriptionService
    private var eventsContinuation: AsyncStream<StreamingTranscriptionEvent>.Continuation?

    private(set) var transcriptionEvents: AsyncStream<StreamingTranscriptionEvent>

    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()
    private let sampleRate: Double = 16000.0
    // Samples trimmed from buffer front; subtract from absolute indices for buffer-relative access.
    private var trimmedSampleCount: Int = 0

    private var asrManager: AsrManager?
    private var decoderLayerCount: Int = 0
    private var languageHint: Language?
    private let agreementEngine: WordAgreementEngine
    private let config: AgreementConfig

    private var transcriptionTask: Task<Void, Never>?
    private var isTranscribing = false
    private var lastTranscribedSampleCount = 0
    private let minimumAudioSamples = ASRConstants.minimumRequiredSamples(forSampleRate: ASRConstants.sampleRate)
    private let minNewSamples = ASRConstants.minimumRequiredSamples(forSampleRate: ASRConstants.sampleRate)

    init(fluidAudioService: FluidAudioTranscriptionService, config: AgreementConfig = AgreementConfig()) {
        self.fluidAudioService = fluidAudioService
        self.config = config
        self.agreementEngine = WordAgreementEngine(config: config)

        var continuation: AsyncStream<StreamingTranscriptionEvent>.Continuation!
        transcriptionEvents = AsyncStream { continuation = $0 }
        eventsContinuation = continuation
    }

    deinit {
        transcriptionTask?.cancel()
        eventsContinuation?.finish()
    }

    func connect(model: any TranscriptionModel, language: String?) async throws {
        let version: AsrModelVersion = FluidAudioModelManager.asrVersion(for: model.name)
        let models = try await fluidAudioService.getOrLoadModels(for: version)

        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        self.asrManager = manager
        self.decoderLayerCount = await manager.decoderLayerCount
        self.languageHint = FluidAudioTranscriptionService.languageHint(from: language, model: model)

        agreementEngine.reset()
        audioBuffer = []
        trimmedSampleCount = 0
        lastTranscribedSampleCount = 0

        startTranscriptionLoop()

        eventsContinuation?.yield(.sessionStarted)
        logger.notice("FluidAudio agreement streaming started for \(model.displayName, privacy: .public)")
    }

    func sendAudioChunk(_ data: Data) async throws {
        let samples = Self.convertToFloat32(data)
        bufferLock.lock()
        audioBuffer.append(contentsOf: samples)
        bufferLock.unlock()
    }

    func commit() async throws {
        transcriptionTask?.cancel()
        await transcriptionTask?.value
        transcriptionTask = nil

        // Run a clean final ASR pass on the unconfirmed audio portion.
        let remainingText = await transcribeRemainingAudio() ?? ""
        eventsContinuation?.yield(.committed(text: remainingText))
    }

    func disconnect() async {
        transcriptionTask?.cancel()
        await transcriptionTask?.value
        transcriptionTask = nil

        await asrManager?.cleanup()
        asrManager = nil
        decoderLayerCount = 0
        languageHint = nil

        bufferLock.lock()
        audioBuffer = []
        trimmedSampleCount = 0
        bufferLock.unlock()
        agreementEngine.reset()

        eventsContinuation?.finish()
        logger.notice("FluidAudio agreement streaming disconnected")
    }

    // MARK: - Private

    private func startTranscriptionLoop() {
        transcriptionTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(
                        (self?.config.transcribeIntervalSeconds ?? 1.0) * 1_000_000_000
                    ))
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                await self?.runTranscriptionPass()
            }
        }
    }

    private func runTranscriptionPass() async {
        guard !isTranscribing else { return }
        guard let asrManager else { return }

        bufferLock.lock()
        let absoluteSampleCount = trimmedSampleCount + audioBuffer.count
        bufferLock.unlock()

        guard absoluteSampleCount - lastTranscribedSampleCount >= minNewSamples else { return }
        guard absoluteSampleCount >= minimumAudioSamples else { return }

        isTranscribing = true
        defer { isTranscribing = false }

        // Seek to the start of the first unconfirmed word so it isn't clipped.
        let seekTime = agreementEngine.hypothesisStartTime > 0
            ? agreementEngine.hypothesisStartTime
            : agreementEngine.confirmedEndTime
        let seekSample = max(0, Int(seekTime * sampleRate))

        bufferLock.lock()
        let bufferRelativeSeek = max(0, seekSample - trimmedSampleCount)
        let sliceEnd = audioBuffer.count
        guard bufferRelativeSeek < sliceEnd else {
            bufferLock.unlock()
            return
        }
        var audioSlice = Array(audioBuffer[bufferRelativeSeek..<sliceEnd])
        bufferLock.unlock()

        // Pad with 1s trailing silence for punctuation capture
        let maxSingleChunkSamples = 240_000
        let trailingSilenceSamples = 16_000
        if audioSlice.count + trailingSilenceSamples <= maxSingleChunkSamples {
            audioSlice += [Float](repeating: 0, count: trailingSilenceSamples)
        }

        guard audioSlice.count >= minimumAudioSamples else { return }

        do {
            var state = TdtDecoderState.make(decoderLayers: decoderLayerCount)
            let result = try await asrManager.transcribe(
                audioSlice,
                decoderState: &state,
                language: languageHint
            )
            lastTranscribedSampleCount = absoluteSampleCount

            guard let tokenTimings = result.tokenTimings, !tokenTimings.isEmpty else {
                if !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    eventsContinuation?.yield(.partial(text: result.text))
                }
                return
            }

            let timeOffset = Double(seekSample) / sampleRate
            let words = WordAgreementEngine.mergeTokensToWords(tokenTimings, timeOffset: timeOffset)
            guard !words.isEmpty else { return }

            let agreementResult = agreementEngine.processTranscriptionResult(words: words, resultConfidence: result.confidence)

            if !agreementResult.newlyConfirmedText.isEmpty {
                let normalizedConfirmed = TextNormalizer.shared.normalizeSentence(agreementResult.newlyConfirmedText)
                eventsContinuation?.yield(.committed(text: normalizedConfirmed))
            }
            if !agreementResult.fullText.isEmpty {
                eventsContinuation?.yield(.partial(text: agreementResult.fullText))
            }

            // Trim audio up to the hypothesis start point, keeping unconfirmed audio intact.
            let newHypothesisStartTime = agreementEngine.hypothesisStartTime
            if newHypothesisStartTime > 0 {
                let safeTrimPoint = max(0, Int(newHypothesisStartTime * sampleRate))
                let samplesToTrim = safeTrimPoint - trimmedSampleCount
                if samplesToTrim > 0 {
                    bufferLock.lock()
                    let actualTrim = min(samplesToTrim, audioBuffer.count)
                    audioBuffer.removeFirst(actualTrim)
                    trimmedSampleCount += actualTrim
                    bufferLock.unlock()
                }
            }

        } catch {
            logger.error("Transcription pass failed: \(error.localizedDescription, privacy: .public)")
            eventsContinuation?.yield(.error(error))
        }
    }

    // Final transcription of audio after the last confirmed word.
    private func transcribeRemainingAudio() async -> String? {
        guard let asrManager else { return nil }

        let seekTime = agreementEngine.hypothesisStartTime > 0
            ? agreementEngine.hypothesisStartTime
            : agreementEngine.confirmedEndTime
        let seekSample = max(0, Int(seekTime * sampleRate))

        bufferLock.lock()
        let bufferRelativeSeek = max(0, seekSample - trimmedSampleCount)
        guard bufferRelativeSeek < audioBuffer.count else {
            bufferLock.unlock()
            return nil
        }
        var samples = Array(audioBuffer[bufferRelativeSeek...])
        bufferLock.unlock()

        guard samples.count >= minimumAudioSamples else { return nil }

        let trailingSilenceSamples = 16_000
        let maxSingleChunkSamples = 240_000
        if samples.count + trailingSilenceSamples <= maxSingleChunkSamples {
            samples += [Float](repeating: 0, count: trailingSilenceSamples)
        }

        do {
            var state = TdtDecoderState.make(decoderLayers: decoderLayerCount)
            let result = try await asrManager.transcribe(
                samples,
                decoderState: &state,
                language: languageHint
            )
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return TextNormalizer.shared.normalizeSentence(text)
        } catch {
            logger.error("Final transcription failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Audio Conversion

    private static func convertToFloat32(_ data: Data) -> [Float] {
        let sampleCount = data.count / MemoryLayout<Int16>.size
        var samples = [Float](repeating: 0, count: sampleCount)
        data.withUnsafeBytes { rawPtr in
            let int16Ptr = rawPtr.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                samples[i] = Float(int16Ptr[i]) / 32767.0
            }
        }
        return samples
    }
}
