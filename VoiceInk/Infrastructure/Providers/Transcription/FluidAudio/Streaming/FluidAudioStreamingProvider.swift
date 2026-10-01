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
    private let confirmationLock = NSLock()
    private var confirmedSegmentCount = 0
    private let minimumConfirmedSegmentsForStreamingFinalization = 3
    private let minimumAudioSamples = ASRConstants.minimumRequiredSamples(forSampleRate: ASRConstants.sampleRate)
    private let minNewSamples = ASRConstants.minimumRequiredSamples(forSampleRate: ASRConstants.sampleRate)

    var stopDisposition: StreamingStopDisposition {
        confirmationLock.withLock {
            confirmedSegmentCount < minimumConfirmedSegmentsForStreamingFinalization
                ? .useBatchFallback
                : .finalizeStreaming
        }
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
        try await TranscriptionDiagnostics.measure("streaming-manager-load", logger: logger) {
            try await manager.loadModels(models)
        }
        self.asrManager = manager
        self.decoderLayerCount = await manager.decoderLayerCount
        self.languageHint = FluidAudioTranscriptionService.languageHint(from: language, model: model)

        agreementEngine.reset()
        audioBuffer = []
        trimmedSampleCount = 0
        lastTranscribedSampleCount = 0
        confirmationLock.withLock {
            confirmedSegmentCount = 0
        }

        startTranscriptionLoop()

        eventsContinuation?.yield(.sessionStarted)
        logger.notice("FluidAudio agreement streaming started for \(model.displayName, privacy: .public)")
    }

    func sendAudioChunk(_ data: Data) async throws {
        let samples = PCMAudioConverter.float32Samples(fromPCM16Data: data)
        bufferLock.withLock {
            audioBuffer.append(contentsOf: samples)
        }
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

        _ = try? await TranscriptionDiagnostics.measure("streaming-manager-cleanup", logger: logger) {
            await asrManager?.cleanup()
        }
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

        let absoluteSampleCount = bufferLock.withLock {
            trimmedSampleCount + audioBuffer.count
        }

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

        guard let audioSlice = bufferLock.withLock({ () -> [Float]? in
            let bufferRelativeSeek = max(0, seekSample - trimmedSampleCount)
            let sliceEnd = audioBuffer.count
            guard bufferRelativeSeek < sliceEnd else {
                return nil
            }
            return Array(audioBuffer[bufferRelativeSeek..<sliceEnd])
        }) else {
            return
        }

        guard audioSlice.count >= minimumAudioSamples else { return }

        do {
            let segments = try await fluidAudioService.detectedSpeechSegments(in: audioSlice)
                ?? [VadSegment(startTime: 0, endTime: Double(audioSlice.count) / sampleRate)]
            guard !segments.isEmpty else {
                lastTranscribedSampleCount = absoluteSampleCount
                return
            }

            var words: [TimedWord] = []
            var textParts: [String] = []
            var passConfidence: Float = 1.0
            var hasUntimedText = false
            for segment in segments {
                try Task.checkCancellation()
                let start = max(0, min(segment.startSample(sampleRate: VadManager.sampleRate), audioSlice.count))
                let end = max(start, min(segment.endSample(sampleRate: VadManager.sampleRate), audioSlice.count))
                guard start < end else { continue }

                var speechAudio = Array(audioSlice[start..<end])
                // Decoder padding is synthetic; recorded silence outside speech segments is excluded.
                speechAudio += [Float](repeating: 0, count: 16_000)
                var state = TdtDecoderState.make(decoderLayers: decoderLayerCount)
                let result = try await TranscriptionDiagnostics.measure(
                    "streaming-prediction", logger: logger, details: "samples=\(speechAudio.count)"
                ) {
                    try await asrManager.transcribe(speechAudio, decoderState: &state, language: languageHint)
                }
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { textParts.append(text) }
                passConfidence = min(passConfidence, result.confidence)
                if let tokenTimings = result.tokenTimings, !tokenTimings.isEmpty {
                    // VAD removes gaps from ASR input, while agreement uses the recording's timeline.
                    let timeOffset = Double(seekSample + start) / sampleRate
                    words += WordAgreementEngine.mergeTokensToWords(tokenTimings, timeOffset: timeOffset)
                } else if !text.isEmpty {
                    hasUntimedText = true
                }
            }
            lastTranscribedSampleCount = absoluteSampleCount

            guard !words.isEmpty, !hasUntimedText else {
                if !textParts.isEmpty {
                    eventsContinuation?.yield(.partial(text: textParts.joined(separator: " ")))
                }
                return
            }

            let agreementResult = agreementEngine.processTranscriptionResult(
                words: words, resultConfidence: passConfidence)

            if !agreementResult.newlyConfirmedText.isEmpty {
                let confirmedText = agreementResult.newlyConfirmedText.trimmingCharacters(
                    in: .whitespacesAndNewlines)
                if !confirmedText.isEmpty {
                    confirmationLock.withLock {
                        confirmedSegmentCount += 1
                    }
                    eventsContinuation?.yield(.committed(text: confirmedText))
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
            logger.error("Transcription pass failed id=\(TranscriptionDiagnostics.recordingID ?? "-", privacy: .public): \(TranscriptionDiagnostics.errorDetails(error, includeUnderlying: false), privacy: .public)")
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

        guard let samples = bufferLock.withLock({ () -> [Float]? in
            let bufferRelativeSeek = max(0, seekSample - trimmedSampleCount)
            guard bufferRelativeSeek < audioBuffer.count else {
                return nil
            }
            return Array(audioBuffer[bufferRelativeSeek...])
        }) else {
            TranscriptionDiagnostics.recording?.add("finalization", "no-remaining-audio")
            return nil
        }

        do {
            var speechAudio = try await fluidAudioService.preparedSpeechAudio(in: samples)
            guard !speechAudio.isEmpty else { return nil }
            // Keep short spoken tails and final punctuation with decoder padding.
            speechAudio += [Float](repeating: 0, count: 16_000)
            var state = TdtDecoderState.make(decoderLayers: decoderLayerCount)
            let result = try await TranscriptionDiagnostics.measure(
                "streaming-final-prediction", logger: logger, details: "samples=\(speechAudio.count)"
            ) {
                try await asrManager.transcribe(speechAudio, decoderState: &state, language: languageHint)
            }
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return text
        } catch {
            logger.error("Final transcription failed id=\(TranscriptionDiagnostics.recordingID ?? "-", privacy: .public): \(TranscriptionDiagnostics.errorDetails(error, includeUnderlying: false), privacy: .public)")
            return nil
        }
    }

}
