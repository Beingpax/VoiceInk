import Foundation
import SwiftUI
import AVFoundation
import SwiftData
import os

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
              case .failed = item.status else { return }

        item.status = .pending
    }

    /// Start processing pending items in the queue sequentially.
    func startProcessing(modelContext: ModelContext, engine: VoiceInkEngine) {
        guard !isProcessingQueue else { return }
        isProcessingQueue = true
        processingGeneration &+= 1
        let generation = processingGeneration

        processingTask = Task { [weak self] in
            guard let self else { return }

            while let item = self.nextPendingItem() {
                guard !Task.isCancelled else { break }
                await self.processItem(item, modelContext: modelContext, engine: engine)
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
        queue.contains { if case .pending = $0.status { return true }; return false }
    }

    // MARK: - Private

    private func nextPendingItem() -> AudioFileQueueItem? {
        queue.first { if case .pending = $0.status { return true }; return false }
    }

    private func processItem(_ item: AudioFileQueueItem, modelContext: ModelContext, engine: VoiceInkEngine) async {
        let serviceRegistry = TranscriptionServiceRegistry(
            modelProvider: engine.whisperModelManager,
            modelsDirectory: engine.whisperModelManager.modelsDirectory,
            modelContext: modelContext
        )

        do {
            guard let currentModel = engine.transcriptionModelManager.currentTranscriptionModel else {
                throw TranscriptionError.noModelSelected
            }

            // Phase: Loading
            item.status = .processing(phase: .loading)
            try Task.checkCancellation()

            // Phase: Processing Audio
            item.status = .processing(phase: .processingAudio)

            let accessing = item.url.startAccessingSecurityScopedResource()
            defer { if accessing { item.url.stopAccessingSecurityScopedResource() } }

            let samples = try await audioProcessor.processAudioToSamples(item.url)
            try Task.checkCancellation()

            let audioAsset = AVURLAsset(url: item.url)
            let duration = CMTimeGetSeconds(try await audioAsset.load(.duration))

            let recordingsDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
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
            var text = try await serviceRegistry.transcribe(audioURL: permanentURL, model: currentModel)
            let transcriptionDuration = Date().timeIntervalSince(transcriptionStart)
            text = TranscriptionOutputFilter.filter(text)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)

            let powerModeManager = PowerModeManager.shared
            let activePowerModeConfig = powerModeManager.currentActiveConfiguration
            let powerModeName = (activePowerModeConfig?.isEnabled == true) ? activePowerModeConfig?.name : nil
            let powerModeEmoji = (activePowerModeConfig?.isEnabled == true) ? activePowerModeConfig?.emoji : nil

            if UserDefaults.standard.bool(forKey: "IsTextFormattingEnabled") {
                text = WhisperTextFormatter.format(text)
            }

            text = WordReplacementService.shared.applyReplacements(to: text, using: modelContext)
            let cleanedText = TranscriptionOutputFilter.applyUserCleanupPreferences(text)
            try Task.checkCancellation()

            // Handle enhancement if enabled
            var transcription: Transcription

            if let enhancementService = engine.enhancementService,
               enhancementService.isEnhancementEnabled,
               enhancementService.isConfigured {
                item.status = .processing(phase: .enhancing)
                do {
                    let (enhancedText, enhancementDuration, promptName) = try await enhancementService.enhance(text)
                    transcription = Transcription(
                        text: cleanedText,
                        duration: duration,
                        enhancedText: enhancedText,
                        audioFileURL: permanentURL.absoluteString,
                        transcriptionModelName: currentModel.displayName,
                        aiEnhancementModelName: enhancementService.getAIService()?.currentModel,
                        promptName: promptName,
                        transcriptionDuration: transcriptionDuration,
                        enhancementDuration: enhancementDuration,
                        aiRequestSystemMessage: enhancementService.lastSystemMessageSent,
                        aiRequestUserMessage: enhancementService.lastUserMessageSent,
                        powerModeName: powerModeName,
                        powerModeEmoji: powerModeEmoji
                    )
                } catch {
                    logger.error("Enhancement failed: \(error.localizedDescription, privacy: .public)")
                    transcription = Transcription(
                        text: cleanedText,
                        duration: duration,
                        enhancedText: "Enhancement failed: \(error.localizedDescription)",
                        audioFileURL: permanentURL.absoluteString,
                        transcriptionModelName: currentModel.displayName,
                        promptName: nil,
                        transcriptionDuration: transcriptionDuration,
                        powerModeName: powerModeName,
                        powerModeEmoji: powerModeEmoji
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
                    powerModeName: powerModeName,
                    powerModeEmoji: powerModeEmoji
                )
            }

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
                logger.error("Transcription error: \(error.localizedDescription, privacy: .public)")
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
            return "No transcription model selected"
        case .transcriptionCancelled:
            return "Transcription was cancelled"
        }
    }
}
