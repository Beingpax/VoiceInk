import Foundation
import SwiftUI
import AVFoundation
import SwiftData
import os

@MainActor
class AudioTranscriptionManager: ObservableObject {
    static let shared = AudioTranscriptionManager()
    
    @Published var isProcessing = false
    @Published var processingPhase: ProcessingPhase = .idle
    @Published var currentTranscription: Transcription?
    @Published var messageLog: String = ""
    @Published var errorMessage: String?
    
    private var currentTask: Task<Void, Error>?
    private var transcriptionService: (any TranscriptionService)?
    private let audioProcessor = AudioProcessor()
    private let serviceFactory = TranscriptionServiceFactory()
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "AudioTranscriptionManager")
    
    enum ProcessingPhase {
        case idle
        case loading
        case processingAudio
        case transcribing
        case enhancing
        case completed
        
        var message: String {
            switch self {
            case .idle:
                return ""
            case .loading:
                return "Loading transcription service..."
            case .processingAudio:
                return "Processing audio file for transcription..."
            case .transcribing:
                return "Transcribing audio..."
            case .enhancing:
                return "Enhancing transcription with AI..."
            case .completed:
                return "Transcription completed!"
            }
        }
    }
    
    private init() {}
    
    func startProcessing(url: URL, modelContext: ModelContext, whisperState: WhisperState) {
        // Cancel any existing processing
        cancelProcessing()
        
        isProcessing = true
        processingPhase = .loading
        messageLog = ""
        errorMessage = nil
        
        currentTask = Task {
            do {
                let serviceType = whisperState.transcriptionServiceType
                
                switch serviceType {
                case .local:
                    guard let currentModel = whisperState.currentModel else {
                        throw TranscriptionError.noModelSelected
                    }
                    
                    let configuration: [String: Any] = ["modelPath": currentModel.url.path]
                    transcriptionService = try await serviceFactory.createService(type: .local, configuration: configuration)
                    
                case .cloud:
                    let configuration: [String: Any] = [
                        "apiKey": whisperState.cloudTranscriptionApiKey,
                        "apiEndpoint": whisperState.cloudTranscriptionApiEndpoint
                    ]
                    transcriptionService = try await serviceFactory.createService(type: .cloud, configuration: configuration)
                }
                
                // Calculate the file duration
                let audioAsset = AVURLAsset(url: url)
                var duration: TimeInterval = 0
                
                if #available(macOS 13.0, *) {
                    let durationValue = try await audioAsset.load(.duration)
                    duration = CMTimeGetSeconds(durationValue)
                } else {
                    duration = CMTimeGetSeconds(audioAsset.duration)
                }
                
                // Create a permanent copy
                let recordingsDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("com.prakashjoshipax.VoiceInk")
                    .appendingPathComponent("Recordings")
                
                let fileName = "transcribed_\(UUID().uuidString).wav"
                let permanentURL = recordingsDirectory.appendingPathComponent(fileName)
                
                try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: url, to: permanentURL)
                
                guard let transcriptionService = transcriptionService else {
                    throw TranscriptionError.serviceInitFailed
                }
                
                // Set language from UserDefaults
                let selectedLanguage = UserDefaults.standard.selectedLanguage
                await transcriptionService.setLanguage(selectedLanguage)
                
                // Process with transcription service
                processingPhase = .transcribing
                messageLog += "Transcribing audio...\n"
                await transcriptionService.setPrompt(whisperState.whisperPrompt.transcriptionPrompt)
                
                // Use direct file URL transcription instead of reading samples
                try await transcriptionService.fullTranscribeFromURL(fileURL: permanentURL)
                
                var transcriptionText = await transcriptionService.getTranscription()
                transcriptionText = transcriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Apply word replacements if enabled
                if UserDefaults.standard.isWordReplacementEnabled {
                    transcriptionText = WordReplacementService.shared.applyReplacements(to: transcriptionText)
                }
                
                // Apply AI enhancement if enabled
                if let enhancementService = whisperState.enhancementService,
                   enhancementService.isEnhancementEnabled,
                   enhancementService.isConfigured
                {
                    processingPhase = .enhancing
                    messageLog += "Enhancing transcription with AI...\n"
                    do {
                        let enhancedText = try await enhancementService.enhance(transcriptionText)
                        
                        // Create and save the transcription
                        let transcription = Transcription(
                            text: transcriptionText,
                            duration: duration,
                            enhancedText: enhancedText,
                            audioFileURL: permanentURL.absoluteString
                        )
                        
                        modelContext.insert(transcription)
                        try modelContext.save()
                        currentTranscription = transcription
                        
                        messageLog += "Transcription complete!\n"
                    } catch {
                        logger.error("Enhancement failed: \(error.localizedDescription)")
                        messageLog += "Enhancement failed: \(error.localizedDescription). Using original transcription.\n"
                        
                        // Save original transcription without enhancement
                        let transcription = Transcription(
                            text: transcriptionText,
                            duration: duration,
                            audioFileURL: permanentURL.absoluteString
                        )
                        
                        modelContext.insert(transcription)
                        try modelContext.save()
                        currentTranscription = transcription
                    }
                } else {
                    // Save the transcription without enhancement
                    let transcription = Transcription(
                        text: transcriptionText,
                        duration: duration,
                        audioFileURL: permanentURL.absoluteString
                    )
                    
                    modelContext.insert(transcription)
                    try modelContext.save()
                    currentTranscription = transcription
                }
                
                processingPhase = .completed
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await finishProcessing()
                
            } catch {
                await handleError(error)
            }
        }
    }
    
    func cancelProcessing() {
        currentTask?.cancel()
        cleanupResources()
    }
    
    private func finishProcessing() {
        isProcessing = false
        processingPhase = .idle
        currentTask = nil
        cleanupResources()
    }
    
    private func handleError(_ error: Error) {
        logger.error("Transcription error: \(error.localizedDescription)")
        errorMessage = error.localizedDescription
        messageLog += "Error: \(error.localizedDescription)\n"
        isProcessing = false
        processingPhase = .idle
        currentTask = nil
        cleanupResources()
    }
    
    private func cleanupResources() {
        if let service = transcriptionService {
            Task {
                await service.releaseResources()
                self.transcriptionService = nil
            }
        }
    }
}

enum TranscriptionError: Error, LocalizedError {
    case noModelSelected
    case transcriptionCancelled
    case serviceInitFailed
    
    var errorDescription: String? {
        switch self {
        case .noModelSelected:
            return "No transcription model selected"
        case .transcriptionCancelled:
            return "Transcription was cancelled"
        case .serviceInitFailed:
            return "Failed to initialize transcription service"
        }
    }
} 
