import AppKit
import AVFoundation
import Foundation
import KeyboardShortcuts
import os
import SwiftData
import SwiftUI

@MainActor
class WhisperState: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isModelLoaded = false
    @Published var messageLog = ""
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
    @Published var isAutoCopyEnabled: Bool = UserDefaults.standard.isAutoCopyEnabled {
        didSet {
            UserDefaults.standard.isAutoCopyEnabled = isAutoCopyEnabled
        }
    }

    @Published var recorderType: String = UserDefaults.standard.recorderType {
        didSet {
            UserDefaults.standard.recorderType = recorderType
        }
    }
    
    @Published var isVisualizerActive = false
    
    @Published var isMiniRecorderVisible = false {
        didSet {
            if isMiniRecorderVisible {
                showRecorderPanel()
            } else {
                hideRecorderPanel()
            }
        }
    }
    
    // Use TranscriptionService protocol instead of specific WhisperContext
    var transcriptionService: (any TranscriptionService)?
    
    // Service factory for creating transcription services
    let serviceFactory = TranscriptionServiceFactory()
    
    // Currently selected transcription service type
    @Published var transcriptionServiceType: TranscriptionServiceType = UserDefaults.standard.transcriptionServiceType {
        didSet {
            UserDefaults.standard.transcriptionServiceType = transcriptionServiceType
            // Release existing service resources when changing type
            Task {
                await cleanupServiceResources()
            }
            // Post notification for language change
            NotificationCenter.default.post(name: .languageDidChange, object: nil)
        }
    }
    
    // Cloud service configuration
    @Published var cloudTranscriptionApiKey: String = UserDefaults.standard.cloudTranscriptionApiKey {
        didSet {
            UserDefaults.standard.cloudTranscriptionApiKey = cloudTranscriptionApiKey
            serviceFactory.updateDefaultCloudConfig(apiKey: cloudTranscriptionApiKey)
        }
    }
    
    @Published var cloudTranscriptionApiEndpoint: String = UserDefaults.standard.cloudTranscriptionApiEndpoint {
        didSet {
            UserDefaults.standard.cloudTranscriptionApiEndpoint = cloudTranscriptionApiEndpoint
            serviceFactory.updateDefaultCloudConfig(apiEndpoint: cloudTranscriptionApiEndpoint)
        }
    }
    
    // Cloud model selection
    @Published var cloudTranscriptionModelName: String = UserDefaults.standard.cloudTranscriptionModelName {
        didSet {
            UserDefaults.standard.cloudTranscriptionModelName = cloudTranscriptionModelName
        }
    }
    
    // Custom language for manual input
    @Published var cloudTranscriptionLanguage: String? = UserDefaults.standard.cloudTranscriptionLanguage {
        didSet {
            UserDefaults.standard.cloudTranscriptionLanguage = cloudTranscriptionLanguage
            // Post notification for language change
            NotificationCenter.default.post(name: .languageDidChange, object: nil)
        }
    }
    
    // Selected language for transcription
    @Published var selectedLanguage: String? = UserDefaults.standard.selectedLanguage {
        didSet {
            UserDefaults.standard.selectedLanguage = selectedLanguage
        }
    }
    
    let recorder = Recorder()
    var recordedFile: URL? = nil
    let whisperPrompt = WhisperPrompt()
    
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
        case serviceCreationFailed
    }
    
    let modelsDirectory: URL
    let recordingsDirectory: URL
    let enhancementService: AIEnhancementService?
    var licenseViewModel: LicenseViewModel
    let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "WhisperState")
    private var transcriptionStartTime: Date?
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
        
        if let savedModelName = UserDefaults.standard.currentModel,
           let savedModel = availableModels.first(where: { $0.name == savedModelName })
        {
            currentModel = savedModel
        }
        
        // Initialize the service factory with cloud configuration
        serviceFactory.updateDefaultCloudConfig(
            apiEndpoint: cloudTranscriptionApiEndpoint,
            apiKey: cloudTranscriptionApiKey
        )
    }
    
    private func createRecordingsDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            messageLog += "Error creating recordings directory: \(error.localizedDescription)\n"
        }
    }
    
    func toggleRecord() async {
        if isRecording {
            logger.notice("🛑 Stopping recording")
            
            await MainActor.run {
                isRecording = false
                isVisualizerActive = false
            }
            
            await recorder.stopRecording()
            
            if let recordedFile {
                let duration = Date().timeIntervalSince(transcriptionStartTime ?? Date())
                if !shouldCancelRecording {
                    await transcribeAudio(recordedFile, duration: duration)
                }
            } else {
                logger.error("❌ No recorded file found after stopping recording")
            }
        } else {
            guard currentModel != nil || transcriptionServiceType == .cloud else {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "No Whisper or Cloud Model Selected "
                    alert.informativeText = "Please select a default model in AI Models tab before recording."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
                return
            }
            
            shouldCancelRecording = false
            
            logger.notice("🎙️ Starting recording")
            requestRecordPermission { [self] granted in
                if granted {
                    Task {
                        do {
                            let file = try FileManager.default.url(for: .documentDirectory,
                                                                   in: .userDomainMask,
                                                                   appropriateFor: nil,
                                                                   create: true)
                                .appending(path: "output.wav")
                            
                            self.recordedFile = file
                            self.transcriptionStartTime = Date()
                            
                            await MainActor.run {
                                self.isRecording = true
                                self.isVisualizerActive = true
                            }
                            
                            async let recordingTask: Void = self.recorder.startRecording(toOutputFile: file, delegate: self)
                            async let windowConfigTask: Void = ActiveWindowService.shared.applyConfigurationForCurrentApp()
                            
                            async let serviceLoadingTask: Void = {
                                if await self.transcriptionService == nil {
                                    logger.notice("🔄 Loading transcription service in parallel with recording")
                                    do {
                                        try await self.loadTranscriptionService()
                                    } catch {
                                        logger.error("❌ Service preloading failed: \(error.localizedDescription)")
                                        await MainActor.run {
                                            self.messageLog += "Error preloading transcription service: \(error.localizedDescription)\n"
                                        }
                                    }
                                }
                            }()
                            
                            try await recordingTask
                            await windowConfigTask
                            
                            if let enhancementService = self.enhancementService,
                               enhancementService.isEnhancementEnabled &&
                               enhancementService.useScreenCaptureContext
                            {
                                await enhancementService.captureScreenContext()
                            }
                            
                            await serviceLoadingTask
                            
                        } catch {
                            await MainActor.run {
                                self.messageLog += "\(error.localizedDescription)\n"
                                self.isRecording = false
                                self.isVisualizerActive = false
                            }
                        }
                    }
                } else {
                    self.messageLog += "Recording permission denied\n"
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
        messageLog += "\(error.localizedDescription)\n"
        isRecording = false
    }
    
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task {
            await onDidFinishRecording(success: flag)
        }
    }
    
    private func onDidFinishRecording(success: Bool) {
        if !success {
            messageLog += "Recording did not finish successfully\n"
        }
    }

    private func transcribeAudio(_ url: URL, duration: TimeInterval) async {
        if shouldCancelRecording { return }

        await MainActor.run {
            isProcessing = true
            isTranscribing = true
            canTranscribe = false
        }

        defer {
            if shouldCancelRecording {
                Task {
                    await cleanupServiceResources()
                }
            }
        }

        // For local transcription, we need a model
        if transcriptionServiceType == .local {
            guard let _ = currentModel else {
                logger.error("❌ Cannot transcribe: No model selected for local transcription")
                messageLog += "Cannot transcribe: No model selected.\n"
                currentError = .modelLoadFailed
                return
            }
        }

        if transcriptionService == nil {
            logger.notice("🔄 Transcription service not loaded yet, attempting to load now")
            do {
                try await loadTranscriptionService()
            } catch {
                logger.error("❌ Failed to load transcription service: \(error.localizedDescription)")
                messageLog += "Failed to load transcription service. Please try again.\n"
                currentError = .modelLoadFailed
                return
            }
        }

        guard let transcriptionService = transcriptionService else {
            logger.error("❌ Cannot transcribe: Transcription service could not be loaded")
            messageLog += "Cannot transcribe: Transcription service could not be loaded after retry.\n"
            currentError = .modelLoadFailed
            return
        }

        logger.notice("🔄 Starting transcription with service type: \(self.transcriptionServiceType.rawValue)")
        do {
            let permanentURL = try saveRecordingPermanently(url)
            let permanentURLString = permanentURL.absoluteString

            if shouldCancelRecording { return }

            messageLog += "Transcribing audio using \(transcriptionServiceType.description)...\n"
            messageLog += "Setting prompt: \(whisperPrompt.transcriptionPrompt)\n"
            await transcriptionService.setPrompt(whisperPrompt.transcriptionPrompt)
            
            let selectedLanguage = switch transcriptionServiceType {
            case .local:
                selectedLanguage
            case .cloud:
                cloudTranscriptionLanguage
            }
            await transcriptionService.setLanguage(selectedLanguage)
            
            if shouldCancelRecording { return }
            
            // Use direct file URL transcription instead of reading samples
            try await transcriptionService.fullTranscribeFromURL(fileURL: permanentURL)
            
            if shouldCancelRecording { return }
            
            var text = await transcriptionService.getTranscription()
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            logger.notice("✅ Transcription completed successfully, length: \(text.count) characters")
            
            if UserDefaults.standard.isWordReplacementEnabled {
                text = WordReplacementService.shared.applyReplacements(to: text)
                logger.notice("✅ Word replacements applied")
            }
            
            if let enhancementService = enhancementService,
               enhancementService.isEnhancementEnabled,
               enhancementService.isConfigured
            {
                do {
                    if shouldCancelRecording { return }
                    
                    messageLog += "Enhancing transcription with AI...\n"
                    let enhancedText = try await enhancementService.enhance(text)
                    messageLog += "Enhancement completed.\n"
                    
                    let newTranscription = Transcription(
                        text: text,
                        duration: duration,
                        enhancedText: enhancedText,
                        audioFileURL: permanentURLString
                    )
                    modelContext.insert(newTranscription)
                    try? modelContext.save()
                    
                    text = enhancedText
                } catch {
                    messageLog += "Enhancement failed: \(error.localizedDescription). Using original transcription.\n"
                    let newTranscription = Transcription(
                        text: text,
                        duration: duration,
                        audioFileURL: permanentURLString
                    )
                    modelContext.insert(newTranscription)
                    try? modelContext.save()
                }
            } else {
                let newTranscription = Transcription(
                    text: text,
                    duration: duration,
                    audioFileURL: permanentURLString
                )
                modelContext.insert(newTranscription)
                try? modelContext.save()
            }
            
            if case .trialExpired = licenseViewModel.licenseState {
                text = """
                Your trial has expired. Upgrade to VoiceInk Pro at tryvoiceink.com/buy
                
                \(text)
                """
            }
            
            messageLog += "Done: \(text)\n"
            
            SoundManager.shared.playStopSound()
            
            if AXIsProcessTrusted() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    CursorPaster.pasteAtCursor(text)
                }
            } else {
                messageLog += "Accessibility permissions not granted. Transcription not pasted automatically.\n"
            }
            
            if isAutoCopyEnabled {
                let success = ClipboardManager.copyToClipboard(text)
                if success {
                    clipboardMessage = "Transcription copied to clipboard"
                } else {
                    clipboardMessage = "Failed to copy to clipboard"
                    messageLog += "Failed to copy transcription to clipboard\n"
                }
            }
            
            await dismissMiniRecorder()
            await cleanupServiceResources()
            
        } catch {
            messageLog += "\(error.localizedDescription)\n"
            currentError = .transcriptionFailed
            
            await cleanupServiceResources()
            await dismissMiniRecorder()
        }
    }

    @Published var currentError: WhisperStateError?
    
    // Load appropriate transcription service based on selected type
    func loadTranscriptionService() async throws {
        logger.notice("🔄 Loading transcription service of type: \(self.transcriptionServiceType.rawValue)")
        
        switch transcriptionServiceType {
        case .local:
            guard let currentModel = currentModel else {
                throw LoadError.couldNotLocateModel
            }
            
            isModelLoading = true
            defer { isModelLoading = false }
            
            let configuration: [String: Any] = ["modelPath": currentModel.url.path]
            transcriptionService = try await serviceFactory.createService(type: .local, configuration: configuration)
            
        case .cloud:
            // Validate API key and endpoint first
            guard !cloudTranscriptionApiKey.isEmpty else {
                logger.error("❌ Unable to load cloud service: API key is empty")
                throw LoadError.serviceCreationFailed
            }
            
            guard !cloudTranscriptionApiEndpoint.isEmpty else {
                logger.error("❌ Unable to load cloud service: Endpoint URL is empty")
                throw LoadError.serviceCreationFailed
            }
            
            // Validate endpoint URL
            guard let url = URL(string: cloudTranscriptionApiEndpoint),
                  url.scheme == "http" || url.scheme == "https"
            else {
                logger.error("❌ Unable to load cloud service: Invalid endpoint URL format")
                throw LoadError.serviceCreationFailed
            }
            
            let configuration: [String: Any] = [
                "apiKey": cloudTranscriptionApiKey,
                "apiEndpoint": cloudTranscriptionApiEndpoint,
                "modelName": cloudTranscriptionModelName
            ]
            
            do {
                transcriptionService = try await serviceFactory.createService(type: .cloud, configuration: configuration)
                await transcriptionService?.setLanguage(selectedLanguage)
                
                isModelLoaded = true
                canTranscribe = true
                logger.notice("✅ Successfully loaded cloud transcription service")
            } catch {
                logger.error("❌ Failed to load cloud service: \(error.localizedDescription)")
                throw LoadError.serviceCreationFailed
            }
        }
        
        isModelLoaded = true
    }

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
    var downloadURL: String {
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)"
    }

    var filename: String {
        "\(name).bin"
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
    static let languageDidChange = Notification.Name("languageDidChange")
}
