import FluidAudio
import Foundation
import os

/// Agreement-based on-device streaming transcription using FluidAudio ASR.
/// Conforms to a `Sendable` protocol: instances are handed between the engine's isolation
/// domains, and internal mutable state is guarded by locks or confined to one task.
final class FluidAudioStreamingProvider: StreamingTranscriptionProvider, @unchecked Sendable {

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
    private let confirmationLock = NSLock()
    private var confirmedSegmentCount = 0
    private let minimumConfirmedSegmentsForStreamingFinalization = 3
    private let minimumAudioSamples = ASRConstants.minimumRequiredSamples(forSampleRate: ASRConstants.sampleRate)
    private let minNewSamples = ASRConstants.minimumRequiredSamples(forSampleRate: ASRConstants.sampleRate)

    var stopDisposition: StreamingStopDisposition {
        confirmationLock.lock()
        defer { confirmationLock.unlock() }
        return confirmedSegmentCount < minimumConfirmedSegmentsForStreamingFinalization
            ? .useBatchFallback
            : .finalizeStreaming
    }

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
        confirmationLock.withLock { confirmedSegmentCount = 0 }

        startTranscriptionLoop()

        eventsContinuation?.yield(.sessionStarted)
        logger.notice("FluidAudio agreement streaming started for \(model.displayName, privacy: .public)")
    }

    func sendAudioChunk(_ data: Data) async throws {
        let samples = PCMAudioConverter.float32Samples(fromPCM16Data: data)
        bufferLock.withLock { audioBuffer.append(contentsOf: samples) }
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

        bufferLock.withLock {
            audioBuffer = []
            trimmedSampleCount = 0
        }
        agreementEngine.reset()

        eventsContinuation?.finish()
        logger.notice("FluidAudio agreement streaming disconnected")
    }

    // MARK: - Private

    private func startTranscriptionLoop() {
        transcriptionTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(
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

        let absoluteSampleCount = bufferLock.withLock { trimmedSampleCount + audioBuffer.count }

        guard absoluteSampleCount - lastTranscribedSampleCount >= minNewSamples else { return }
        guard absoluteSampleCount >= minimumAudioSamples else { return }

        isTranscribing = true
        defer { isTranscribing = false }

        // Seek to the start of the first unconfirmed word so it isn't clipped.
        let seekTime =
            agreementEngine.hypothesisStartTime > 0
            ? agreementEngine.hypothesisStartTime
            : agreementEngine.confirmedEndTime
        let seekSample = max(0, Int(seekTime * sampleRate))

        let slice: [Float]? = bufferLock.withLock {
            let bufferRelativeSeek = max(0, seekSample - trimmedSampleCount)
            let sliceEnd = audioBuffer.count
            guard bufferRelativeSeek < sliceEnd else { return nil }
            return Array(audioBuffer[bufferRelativeSeek..<sliceEnd])
        }
        guard var audioSlice = slice else { return }

        // Pad with 1s trailing silence for punctuation capture
        let trailingSilenceSamples = 16_000
        audioSlice += [Float](repeating: 0, count: trailingSilenceSamples)

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

            let agreementResult = agreementEngine.processTranscriptionResult(
                words: words, resultConfidence: result.confidence)

            if !agreementResult.newlyConfirmedText.isEmpty {
                let normalizedConfirmed = TextNormalizer.shared.normalizeSentence(agreementResult.newlyConfirmedText)
                if !normalizedConfirmed.isEmpty {
                    confirmationLock.withLock { confirmedSegmentCount += 1 }
                    eventsContinuation?.yield(.committed(text: normalizedConfirmed))
                }
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
                    bufferLock.withLock {
                        let actualTrim = min(samplesToTrim, audioBuffer.count)
                        audioBuffer.removeFirst(actualTrim)
                        trimmedSampleCount += actualTrim
                    }
                }
            }

        } catch {
            logger.error("Transcription pass failed: \(error, privacy: .public)")
            eventsContinuation?.yield(.error(error))
        }
    }

    // Final transcription of audio after the last confirmed word.
    private func transcribeRemainingAudio() async -> String? {
        guard let asrManager else { return nil }

        let seekTime =
            agreementEngine.hypothesisStartTime > 0
            ? agreementEngine.hypothesisStartTime
            : agreementEngine.confirmedEndTime
        let seekSample = max(0, Int(seekTime * sampleRate))

        let tail: [Float]? = bufferLock.withLock {
            let bufferRelativeSeek = max(0, seekSample - trimmedSampleCount)
            guard bufferRelativeSeek < audioBuffer.count else { return nil }
            return Array(audioBuffer[bufferRelativeSeek...])
        }
        guard var samples = tail else { return nil }

        // A short spoken tail still needs enough input for FluidAudio. Padding before
        // transcription keeps that tail instead of rejecting it for being under 300 ms.
        let trailingSilenceSamples = 16_000
        samples += [Float](repeating: 0, count: trailingSilenceSamples)

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
            logger.error("Final transcription failed: \(error, privacy: .public)")
            return nil
        }
    }

}
