import Foundation
import SwiftUI
import AVFoundation
import SwiftData
import AppKit
import KeyboardShortcuts
import os

@MainActor
class WhisperState: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isModelLoaded = false
    @Published var canTranscribe = false
    @Published var isRecording = false
    @Published var currentModel: WhisperModel?
    @Published var isModelLoading = false
    @Published var availableModels: [WhisperModel] = []
    @Published var predefinedModels: [PredefinedModel] = PredefinedModels.models
    @Published var clipboardMessage = ""
    @Published var miniRecorderError: String?
    @Published var isProcessing = false
    @Published var shouldCancelRecording = false
    @Published var isTranscribing = false
    @Published var isAutoCopyEnabled: Bool = UserDefaults.standard.object(forKey: "IsAutoCopyEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isAutoCopyEnabled, forKey: "IsAutoCopyEnabled")
        }
    }
    @Published var recorderType: String = UserDefaults.standard.string(forKey: "RecorderType") ?? "mini" {
        didSet {
            UserDefaults.standard.set(recorderType, forKey: "RecorderType")
        }
    }
    
    @Published var isVisualizerActive = false
    @Published var isMeetingRecording: Bool = false
    
    @Published var isMiniRecorderVisible = false {
        didSet {
            if isMiniRecorderVisible {
                showRecorderPanel()
            } else {
                hideRecorderPanel()
            }
        }
    }
    
    var whisperContext: WhisperContext?
    let recorder = Recorder()
    var recordedFile: URL? = nil
    let whisperPrompt = WhisperPrompt()
    
    // Prompt detection service for trigger word handling
    private let promptDetectionService = PromptDetectionService()
    
    let modelContext: ModelContext
    
    private var modelUrl: URL? {
        let possibleURLs = [
            Bundle.main.url(forResource: "ggml-base.en", withExtension: "bin", subdirectory: "Models"),
            Bundle.main.url(forResource: "ggml-base.en", withExtension: "bin"),
            Bundle.main.bundleURL.appendingPathComponent("Models/ggml-base.en.bin")
        ]
        
        for url in possibleURLs {
            if let url = url, FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }
    
    private enum LoadError: Error {
        case couldNotLocateModel
    }
    
    let modelsDirectory: URL
    let recordingsDirectory: URL
    let enhancementService: AIEnhancementService?
    var licenseViewModel: LicenseViewModel
    let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "WhisperState")
    var notchWindowManager: NotchWindowManager?
    var miniWindowManager: MiniWindowManager?
    
    // For model progress tracking
    @Published var downloadProgress: [String: Double] = [:]
    
    init(modelContext: ModelContext, enhancementService: AIEnhancementService? = nil) {
        self.modelContext = modelContext
        self.modelsDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.prakashjoshipax.VoiceInk")
            .appendingPathComponent("WhisperModels")
        self.recordingsDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.prakashjoshipax.VoiceInk")
            .appendingPathComponent("Recordings")
        self.enhancementService = enhancementService
        self.licenseViewModel = LicenseViewModel()
        
        super.init()
        
        setupNotifications()
        createModelsDirectoryIfNeeded()
        createRecordingsDirectoryIfNeeded()
        loadAvailableModels()
        
        if let savedModelName = UserDefaults.standard.string(forKey: "CurrentModel"),
           let savedModel = availableModels.first(where: { $0.name == savedModelName }) {
            currentModel = savedModel
        }
    }
    
    private func createRecordingsDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            logger.error("Error creating recordings directory: \(error.localizedDescription)")
        }
    }
    
    func toggleRecord(forMeeting: Bool = false) async {
        if isRecording {
            logger.notice("🛑 Stopping recording")
            await MainActor.run {
                isRecording = false
                isVisualizerActive = false
            }
            await recorder.stopRecording()
            if let recordedFile {
                if !shouldCancelRecording {
                    await transcribeAudio(recordedFile)
                } else {
                    logger.info("🛑 Transcription and paste aborted in toggleRecord due to shouldCancelRecording flag.")
                    await MainActor.run {
                        isProcessing = false
                        isTranscribing = false
                        canTranscribe = true
                    }
                    await cleanupModelResources()
                }
            } else {
                logger.error("❌ No recorded file found after stopping recording")
            }
        } else {
            self.isMeetingRecording = forMeeting
            guard currentModel != nil else {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "No Whisper Model Selected"
                    alert.informativeText = "Please select a default whisper model in AI Models tab before recording."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
                return
            }
            shouldCancelRecording = false
            logger.notice("🎙️ Starting recording sequence...")
            requestRecordPermission { [self] granted in
                if granted {
                    Task {
                        do {
                            // --- Prepare temporary file URL within Application Support base directory ---
                            let baseAppSupportDirectory = self.recordingsDirectory.deletingLastPathComponent()
                            let file = baseAppSupportDirectory.appendingPathComponent("output.wav")
                            // Ensure the base directory exists
                            try? FileManager.default.createDirectory(at: baseAppSupportDirectory, withIntermediateDirectories: true)
                            // Clean up any old temporary file first
                            self.recordedFile = file

                            try await self.recorder.startRecording(toOutputFile: file)
                            self.logger.notice("✅ Audio engine started successfully.")

                            await MainActor.run {
                                self.isRecording = true
                                self.isVisualizerActive = true
                            }
                            
                            await ActiveWindowService.shared.applyConfigurationForCurrentApp()

                            if let currentModel = await self.currentModel, await self.whisperContext == nil {
                                do {
                                    try await self.loadModel(currentModel)
                                } catch {
                                    self.logger.error("❌ Model loading failed: \(error.localizedDescription)")
                                }
                            }

                            if let enhancementService = self.enhancementService,
                               enhancementService.isEnhancementEnabled &&
                               enhancementService.useScreenCaptureContext {
                                await enhancementService.captureScreenContext()
                            }

                        } catch {
                            self.logger.error("❌ Failed to start recording: \(error.localizedDescription)")
                            await MainActor.run {
                                self.isRecording = false
                                self.isVisualizerActive = false
                            }
                            if let url = self.recordedFile {
                                try? FileManager.default.removeItem(at: url)
                                self.recordedFile = nil
                                self.logger.notice("🗑️ Cleaned up temporary recording file after failed start.")
                            }
                        }
                    }
                } else {
                    logger.error("❌ Recording permission denied.")
                }
            }
        }
    }
    
    private func requestRecordPermission(response: @escaping (Bool) -> Void) {
#if os(macOS)
        response(true)
#else
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            response(granted)
        }
#endif
    }
    
    // MARK: AVAudioRecorderDelegate
    
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error {
            Task {
                await handleRecError(error)
            }
        }
    }
    
    private func handleRecError(_ error: Error) {
        logger.error("Recording error: \(error.localizedDescription)")
        isRecording = false
    }
    
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task {
            await onDidFinishRecording(success: flag)
        }
    }
    
    private func onDidFinishRecording(success: Bool) {
        if !success {
            logger.error("Recording did not finish successfully")
        }
    }

    private func transcribeAudio(_ url: URL) async {
        if shouldCancelRecording {
            logger.info("🎤 Transcription and paste aborted at the beginning of transcribeAudio due to shouldCancelRecording flag.")
            await MainActor.run {
                isProcessing = false
                isTranscribing = false
                canTranscribe = true
            }
            await cleanupModelResources()
            return
        }
        await MainActor.run {
            isProcessing = true
            isTranscribing = true
            canTranscribe = false
        }
        defer {
            if shouldCancelRecording {
                Task {
                    await cleanupModelResources()
                }
            }
        }
        guard let currentModel = currentModel else {
            logger.error("❌ Cannot transcribe: No model selected")
            currentError = .modelLoadFailed
            return
        }
        if whisperContext == nil {
            logger.notice("🔄 Model not loaded yet, attempting to load now: \(currentModel.name)")
            do {
                try await loadModel(currentModel)
            } catch {
                logger.error("❌ Failed to load model: \(currentModel.name) - \(error.localizedDescription)")
                currentError = .modelLoadFailed
                return
            }
        }
        guard let whisperContext = whisperContext else {
            logger.error("❌ Cannot transcribe: Model could not be loaded")
            currentError = .modelLoadFailed
            return
        }
        logger.notice("🔄 Starting transcription with model: \(currentModel.name)")
        do {
            let permanentURL = try saveRecordingPermanently(url)
            let permanentURLString = permanentURL.absoluteString
            if shouldCancelRecording { return }
            let data = try readAudioSamples(url)
            if shouldCancelRecording { return }
            
            // Get the actual audio duration from the file
            let audioAsset = AVURLAsset(url: url)
            let actualDuration = CMTimeGetSeconds(try await audioAsset.load(.duration))
            logger.notice("📊 Audio file duration: \(actualDuration) seconds")
            
            // Ensure we're using the most recent prompt from UserDefaults
            let currentPrompt = UserDefaults.standard.string(forKey: "TranscriptionPrompt") ?? whisperPrompt.transcriptionPrompt
            await whisperContext.setPrompt(currentPrompt)
            
            if shouldCancelRecording { return }
            await whisperContext.fullTranscribe(samples: data)
            if shouldCancelRecording { return }
            var text = await whisperContext.getTranscription()
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            logger.notice("✅ Transcription completed successfully, length: \(text.count) characters")
            if UserDefaults.standard.bool(forKey: "IsWordReplacementEnabled") {
                text = WordReplacementService.shared.applyReplacements(to: text)
                logger.notice("✅ Word replacements applied")
            }
            
            var promptDetectionResult: PromptDetectionService.PromptDetectionResult? = nil
            let originalText = text 
            
            if let enhancementService = enhancementService, enhancementService.isConfigured {
                let detectionResult = promptDetectionService.analyzeText(text, with: enhancementService)
                promptDetectionResult = detectionResult
                await promptDetectionService.applyDetectionResult(detectionResult, to: enhancementService)
            }
            
            if let enhancementService = enhancementService,
               enhancementService.isEnhancementEnabled,
               enhancementService.isConfigured {
                do {
                    if shouldCancelRecording { return }
                    // Use processed text (without trigger words) for AI enhancement
                    let textForAI = promptDetectionResult?.processedText ?? text
                    let enhancedText = try await enhancementService.enhance(textForAI)
                    let newTranscription = Transcription(
                        text: originalText, 
                        duration: actualDuration,
                        enhancedText: enhancedText,
                        audioFileURL: permanentURLString,
                        isMeeting: self.isMeetingRecording
                    )
                    modelContext.insert(newTranscription)
                    try? modelContext.save()
                    text = enhancedText 
                } catch {
                    let newTranscription = Transcription(
                        text: originalText,
                        duration: actualDuration,
                        audioFileURL: permanentURLString,
                        isMeeting: self.isMeetingRecording
                    )
                    modelContext.insert(newTranscription)
                    try? modelContext.save()
                }
            } else {
                let newTranscription = Transcription(
                    text: originalText,
                    duration: actualDuration,
                    audioFileURL: permanentURLString,
                    isMeeting: self.isMeetingRecording
                )
                modelContext.insert(newTranscription)
                try? modelContext.save()
            }
            if case .trialExpired = licenseViewModel.licenseState {
                text = """
                    Your trial has expired. Upgrade to VoiceInk Pro at tryvoiceink.com/buy
                    \n\(text)
                    """
            }

            // Add a space to the end of the text
            text += " "

            SoundManager.shared.playStopSound()
            if AXIsProcessTrusted() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    CursorPaster.pasteAtCursor(text)
                }
            }
            if isAutoCopyEnabled {
                let success = ClipboardManager.copyToClipboard(text)
                if success {
                    clipboardMessage = "Transcription copied to clipboard"
                } else {
                    clipboardMessage = "Failed to copy to clipboard"
                }
            }
            try? FileManager.default.removeItem(at: url)
            
            if let result = promptDetectionResult, 
               let enhancementService = enhancementService, 
               result.shouldEnableAI {
                await promptDetectionService.restoreOriginalSettings(result, to: enhancementService)
            }
            
            await dismissMiniRecorder()
            self.isMeetingRecording = false
            await cleanupModelResources()
            
        } catch {
            currentError = .transcriptionFailed
            await cleanupModelResources()
            await dismissMiniRecorder()
        }
    }

    private func readAudioSamples(_ url: URL) throws -> [Float] {
        return try decodeWaveFile(url)
    }

    private func decodeWaveFile(_ url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        let floats = stride(from: 44, to: data.count, by: 2).map {
            return data[$0..<$0 + 2].withUnsafeBytes {
                let short = Int16(littleEndian: $0.load(as: Int16.self))
                return max(-1.0, min(Float(short) / 32767.0, 1.0))
            }
        }
        return floats
    }

    @Published var currentError: WhisperStateError?

    func getEnhancementService() -> AIEnhancementService? {
        return enhancementService
    }

    private func saveRecordingPermanently(_ tempURL: URL) throws -> URL {
        let fileName = "\(UUID().uuidString).wav"
        let permanentURL = recordingsDirectory.appendingPathComponent(fileName)
        try FileManager.default.copyItem(at: tempURL, to: permanentURL)
        return permanentURL
    }
}

struct WhisperModel: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    var coreMLEncoderURL: URL? // Path to the unzipped .mlmodelc directory
    var isCoreMLDownloaded: Bool { coreMLEncoderURL != nil }
    
    var downloadURL: String {
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)"
    }
    
    var filename: String {
        "\(name).bin"
    }
    
    // Core ML related properties
    var coreMLZipDownloadURL: String? {
        // Only non-quantized models have Core ML versions
        guard !name.contains("q5") && !name.contains("q8") else { return nil }
        return "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(name)-encoder.mlmodelc.zip"
    }
    
    var coreMLEncoderDirectoryName: String? {
        guard coreMLZipDownloadURL != nil else { return nil }
        return "\(name)-encoder.mlmodelc"
    }
}

private class TaskDelegate: NSObject, URLSessionTaskDelegate {
    private let continuation: CheckedContinuation<Void, Never>
    
    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        continuation.resume()
    }
}

extension Notification.Name {
    static let toggleMiniRecorder = Notification.Name("toggleMiniRecorder")
}
