import AVFoundation
import Foundation
import SwiftData
import SwiftUI
import os

/// How the Transcribe tab identifies speakers in imported audio.
enum TranscribeDiarizationMode: String, CaseIterable {
    case off
    case auto
    case voice
    case stereo

    /// Resolves the persisted mode, honoring the pre-menu boolean toggle.
    static var current: TranscribeDiarizationMode {
        if let raw = UserDefaults.standard.string(forKey: "TranscribeDiarizationMode"),
            let mode = TranscribeDiarizationMode(rawValue: raw)
        {
            return mode
        }
        return UserDefaults.standard.bool(forKey: "TranscribeDiarizationEnabled") ? .auto : .off
    }

    var label: String {
        switch self {
        case .off: return "Off"
        case .auto: return "Auto"
        case .voice: return "Voice AI"
        case .stereo: return "Stereo"
        }
    }

    var help: String {
        switch self {
        case .off: return "No speaker identification"
        case .auto: return "Stereo channels when each speaker has their own channel, Voice AI otherwise"
        case .voice: return "Neural voice clustering (works on any audio)"
        case .stereo: return "One speaker per stereo channel (telephony recordings); off for mono files"
        }
    }
}

@MainActor
class AudioTranscriptionManager: ObservableObject {
    static let shared = AudioTranscriptionManager()

    // MARK: - Published State

    @Published var queue: [AudioFileQueueItem] = []
    @Published var isProcessingQueue = false
    @Published var lastCompletedItemId: UUID?

    // MARK: - Private

    private var processingTask: Task<Void, Never>?
    private var processingGeneration: UInt64 = 0
    private let audioProcessor = AudioProcessor()
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "AudioTranscriptionManager")

    private init() {}

    // MARK: - Queue Management

    /// Add one or more audio file URLs to the queue. Invalid files are silently skipped.
    func addToQueue(urls: [URL]) {
        for url in urls {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            guard SupportedMedia.isSupported(url: url) else { continue }

            // Avoid adding the same file path twice if it's already pending/processing
            let path = url.standardizedFileURL.path
            if queue.contains(where: { $0.url.standardizedFileURL.path == path && !$0.status.isTerminal }) {
                continue
            }

            let item = AudioFileQueueItem(url: url)
            queue.append(item)
        }
    }

    /// Remove a pending item from the queue.
    func removeFromQueue(id: UUID) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        let item = queue[index]

        // Only allow removing pending items
        guard case .pending = item.status else { return }

        queue.remove(at: index)
    }

    /// Clear all items from the queue, cancelling any in-progress work.
    func clearAll() {
        cancelProcessing()
        queue.removeAll()
        lastCompletedItemId = nil
    }

    /// Retry a failed item by resetting it to pending and re-enqueuing.
    func retryItem(id: UUID) {
        guard let item = queue.first(where: { $0.id == id }),
            case .failed = item.status
        else { return }

        item.status = .pending
    }

    /// Start processing pending items in the queue sequentially.
    func startProcessing(modelContext: ModelContext, engine: VoiceInkEngine, mode: ModeConfig) {
        guard !isProcessingQueue else { return }
        isProcessingQueue = true
        processingGeneration &+= 1
        let generation = processingGeneration

        processingTask = Task { [weak self] in
            guard let self else { return }

            while let item = self.nextPendingItem() {
                guard !Task.isCancelled else { break }
                await self.processItem(item, modelContext: modelContext, engine: engine, mode: mode)
            }

            if self.processingGeneration == generation {
                self.isProcessingQueue = false
            }
        }
    }

    func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
        isProcessingQueue = false

        // Reset any in-progress items back to pending
        for item in queue {
            if case .processing = item.status {
                item.status = .pending
            }
        }
    }

    var hasPendingItems: Bool {
        queue.contains {
            if case .pending = $0.status { return true }
            return false
        }
    }

    // MARK: - Private

    /// Peak-normalizes one channel so a quiet call participant gets full ASR
    /// signal level regardless of how loud the other channel is.
    private static func normalized(_ samples: [Float]) -> [Float] {
        let maxSample = samples.map(abs).max() ?? 0
        guard maxSample > 0 else { return samples }
        return samples.map { $0 / maxSample }
    }

    /// Keeps only words whose time span has audible signal in the (normalized)
    /// channel they came from — hallucinated words sit on top of silence.
    /// The span is padded and checked frame by frame so slightly-off word
    /// timestamps (e.g. from inverse text normalization) don't drop real words.
    private static func wordsWithSignal(
        _ words: [WordTiming], samples: [Float], sampleRate: Double = 16000
    ) -> [WordTiming] {
        let padding = 0.3
        let frameSize = Int(sampleRate * 0.05)
        return words.filter { word in
            let start = max(0, Int((word.start - padding) * sampleRate))
            let end = min(samples.count, Int((word.end + padding) * sampleRate))
            guard end > start else { return false }
            var frameStart = start
            while frameStart < end {
                let frameEnd = min(end, frameStart + frameSize)
                var sum: Float = 0
                for i in frameStart..<frameEnd {
                    sum += samples[i] * samples[i]
                }
                if (sum / Float(frameEnd - frameStart)).squareRoot() > 0.012 {
                    return true
                }
                frameStart = frameEnd
            }
            return false
        }
    }

    private func nextPendingItem() -> AudioFileQueueItem? {
        queue.first {
            if case .pending = $0.status { return true }
            return false
        }
    }

    private func processItem(
        _ item: AudioFileQueueItem, modelContext: ModelContext, engine: VoiceInkEngine, mode: ModeConfig
    ) async {
        let serviceRegistry = TranscriptionServiceRegistry(
            modelProvider: engine.whisperModelManager,
            modelsDirectory: engine.whisperModelManager.modelsDirectory,
            modelContext: modelContext
        )

        do {
            guard
                let transcriptionConfiguration = ModeRuntimeResolver.transcriptionConfiguration(
                    mode: mode,
                    transcriptionModelManager: engine.transcriptionModelManager
                )
            else {
                throw TranscriptionError.noModelSelected
            }
            let currentModel = transcriptionConfiguration.model

            // Phase: Loading
            item.status = .processing(phase: .loading)
            try Task.checkCancellation()

            // Phase: Processing Audio
            item.status = .processing(phase: .processingAudio)

            let accessing = item.url.startAccessingSecurityScopedResource()
            defer { if accessing { item.url.stopAccessingSecurityScopedResource() } }

            let samples = try await audioProcessor.processAudioToSamples(item.url)
            try Task.checkCancellation()

            // Diarization runs concurrently with transcription on the same 16kHz samples.
            // Stereo files with one participant per channel (telephony recordings)
            // get exact channel-based separation; everything else uses the neural
            // diarizer. Channels are extracted here, while the security-scoped
            // file access is still held.
            // Speaker identification strategy:
            //  - stereo file with one participant per channel → one ASR pass per
            //    channel (exact attribution, and a quiet participant isn't
            //    masked by the loud one in the mono downmix)
            //  - otherwise → neural diarization, concurrent with transcription
            let diarizationMode = TranscribeDiarizationMode.current
            let stereoChannels =
                (diarizationMode == .auto || diarizationMode == .stereo)
                ? audioProcessor.extractStereoChannels(item.url) : nil
            if diarizationMode == .stereo, stereoChannels == nil {
                logger.notice("Stereo diarization selected but file has no distinct channels; skipping")
            }
            let neuralDiarizationTask: Task<[SpeakerSegment], Error>? =
                (diarizationMode == .voice || (diarizationMode == .auto && stereoChannels == nil))
                ? Task.detached(priority: .userInitiated) {
                    try await SpeakerDiarizationService.shared.diarize(samples: samples)
                }
                : nil
            defer { neuralDiarizationTask?.cancel() }

            let audioAsset = AVURLAsset(url: item.url)
            let duration = CMTimeGetSeconds(try await audioAsset.load(.duration))

            let recordingsDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[
                0
            ]
            .appendingPathComponent("com.prakashjoshipax.VoiceInk")
            .appendingPathComponent("Recordings")

            let fileName = "transcribed_\(UUID().uuidString).wav"
            let permanentURL = recordingsDirectory.appendingPathComponent(fileName)

            try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
            try audioProcessor.saveSamplesAsWav(samples: samples, to: permanentURL)
            try Task.checkCancellation()

            // Phase: Transcribing
            item.status = .processing(phase: .transcribing)
            let transcriptionStart = Date()
            var text: String
            var wordTimings: [WordTiming]?
            var speakerUtterances: [SpeakerUtterance]?

            if let stereoChannels {
                // Dual-channel transcription: each channel normalized and
                // transcribed on its own, then merged on the shared timeline.
                var requestContext = transcriptionConfiguration.requestContext
                requestContext.preservesTimeline = true

                let tempDirectory = FileManager.default.temporaryDirectory
                let leftURL = tempDirectory.appendingPathComponent("channel_L_\(UUID().uuidString).wav")
                let rightURL = tempDirectory.appendingPathComponent("channel_R_\(UUID().uuidString).wav")
                defer {
                    try? FileManager.default.removeItem(at: leftURL)
                    try? FileManager.default.removeItem(at: rightURL)
                }
                let leftSamples = Self.normalized(stereoChannels.left)
                let rightSamples = Self.normalized(stereoChannels.right)
                try audioProcessor.saveSamplesAsWav(samples: leftSamples, to: leftURL)
                try audioProcessor.saveSamplesAsWav(samples: rightSamples, to: rightURL)

                let leftResult = try await serviceRegistry.transcribeDetailed(
                    audioURL: leftURL, model: currentModel, context: requestContext)
                try Task.checkCancellation()
                let rightResult = try await serviceRegistry.transcribeDetailed(
                    audioURL: rightURL, model: currentModel, context: requestContext)

                // With VAD off, engines hallucinate words over silence; drop any
                // word whose span carries no actual signal in its own channel.
                var merged: [WordTiming] = []
                for var word in Self.wordsWithSignal(leftResult.words ?? [], samples: leftSamples) {
                    word.speaker = "1"
                    merged.append(word)
                }
                for var word in Self.wordsWithSignal(rightResult.words ?? [], samples: rightSamples) {
                    word.speaker = "2"
                    merged.append(word)
                }
                merged.sort { $0.start < $1.start }

                if merged.isEmpty {
                    // Engine without word timings: keep both sides, unattributed.
                    text = [leftResult.text, rightResult.text]
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n")
                } else {
                    wordTimings = merged
                    let utterances = SpeakerAlignment.channelUtterances(from: merged)
                    speakerUtterances = utterances
                    text = utterances.map(\.text).joined(separator: " ")
                }
            } else {
                var requestContext = transcriptionConfiguration.requestContext
                requestContext.preservesTimeline = neuralDiarizationTask != nil
                let detailedResult = try await serviceRegistry.transcribeDetailed(
                    audioURL: permanentURL,
                    model: currentModel,
                    context: requestContext
                )
                text = detailedResult.text
                wordTimings = detailedResult.words

                if let neuralDiarizationTask {
                    item.status = .processing(phase: .diarizing)
                    do {
                        let speakerSegments = try await neuralDiarizationTask.value
                        if let words = wordTimings, !words.isEmpty, !speakerSegments.isEmpty {
                            let assigned = SpeakerAlignment.assignSpeakers(words: words, segments: speakerSegments)
                            wordTimings = assigned
                            speakerUtterances = SpeakerAlignment.utterances(from: assigned)
                        } else {
                            logger.notice(
                                "Diarization finished but the engine returned no word timings; skipping speaker assignment"
                            )
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        // Diarization failure must not lose the transcription.
                        logger.error("Diarization failed: \(error, privacy: .public)")
                    }
                }
            }
            let transcriptionDuration = Date().timeIntervalSince(transcriptionStart)
            try Task.checkCancellation()
            text = TranscriptionOutputFilter.filter(text)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)

            let modeMetadata = transcriptionConfiguration.metadata
            let formattingConfiguration = ModeRuntimeResolver.transcriptionFormattingConfiguration(mode: mode)

            if formattingConfiguration.isTextFormattingEnabled {
                text = ParagraphFormatter.format(text)
            }

            text = WordReplacementService.shared.applyReplacements(to: text, using: modelContext)
            let cleanedText = text
            try Task.checkCancellation()

            // Handle enhancement if enabled
            var transcription: Transcription

            let enhancementConfiguration = engine.enhancementService
                .flatMap { enhancementService in
                    enhancementService.getAIService().map { aiService in
                        ModeRuntimeResolver.currentEnhancementConfiguration(
                            mode: mode,
                            enhancementService: enhancementService,
                            aiService: aiService
                        )
                    }
                }

            if let enhancementService = engine.enhancementService,
                let enhancementConfiguration,
                enhancementConfiguration.isEnabled,
                enhancementService.isConfigured(for: enhancementConfiguration)
            {
                item.status = .processing(phase: .enhancing)
                do {
                    let enhancementResult = try await enhancementService.enhance(
                        text,
                        configuration: enhancementConfiguration
                    )
                    transcription = Transcription(
                        text: cleanedText,
                        duration: duration,
                        enhancedText: enhancementResult.text,
                        audioFileURL: permanentURL.absoluteString,
                        transcriptionModelName: currentModel.displayName,
                        aiEnhancementModelName: enhancementConfiguration.modelName
                            ?? enhancementConfiguration.provider?.defaultModel,
                        promptName: enhancementResult.promptName,
                        transcriptionDuration: transcriptionDuration,
                        enhancementDuration: enhancementResult.duration,
                        aiRequestSystemMessage: enhancementResult.systemMessage,
                        aiRequestUserMessage: enhancementResult.userMessage,
                        modeName: modeMetadata.name,
                        modeEmoji: modeMetadata.emoji
                    )
                } catch {
                    let failureMessage = EnhancementFailureFormatter.message(for: error)
                    transcription = Transcription(
                        text: cleanedText,
                        duration: duration,
                        enhancedText: failureMessage,
                        audioFileURL: permanentURL.absoluteString,
                        transcriptionModelName: currentModel.displayName,
                        promptName: nil,
                        transcriptionDuration: transcriptionDuration,
                        modeName: modeMetadata.name,
                        modeEmoji: modeMetadata.emoji
                    )
                }
            } else {
                transcription = Transcription(
                    text: cleanedText,
                    duration: duration,
                    audioFileURL: permanentURL.absoluteString,
                    transcriptionModelName: currentModel.displayName,
                    promptName: nil,
                    transcriptionDuration: transcriptionDuration,
                    modeName: modeMetadata.name,
                    modeEmoji: modeMetadata.emoji
                )
            }

            transcription.wordTimings = wordTimings
            transcription.speakerUtterances = speakerUtterances

            modelContext.insert(transcription)
            try modelContext.save()
            NotificationCenter.default.post(name: .transcriptionCreated, object: transcription)
            NotificationCenter.default.post(name: .transcriptionCompleted, object: transcription)

            item.transcription = transcription
            item.status = .completed
            lastCompletedItemId = item.id

        } catch {
            if Task.isCancelled || error is CancellationError {
                item.status = .pending
            } else {
                logger.error("Transcription error: \(error, privacy: .public)")
                item.status = .failed(message: error.localizedDescription)
            }
        }

        await serviceRegistry.cleanup()
    }
}

enum TranscriptionError: Error, LocalizedError {
    case noModelSelected
    case transcriptionCancelled

    var errorDescription: String? {
        switch self {
        case .noModelSelected:
            return String(localized: "No transcription model selected")
        case .transcriptionCancelled:
            return String(localized: "Transcription was cancelled")
        }
    }
}
