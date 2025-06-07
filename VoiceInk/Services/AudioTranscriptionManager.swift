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
    @Published var useCloudService: Bool = false

    private var currentTask: Task<Void, Error>?
    var cloudService: CloudTranscriptionServiceProtocol // Changed to protocol, made internal for testing access
    private var whisperContext: WhisperContext?
    private let audioProcessor = AudioProcessor()
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "AudioTranscriptionManager")

    // Internal initializer for testing
    internal init(cloudService: CloudTranscriptionServiceProtocol = CloudTranscriptionService()) {
        self.cloudService = cloudService
    }

    // Keep the private init for the singleton `shared` instance
    private init() {
        self.cloudService = CloudTranscriptionService()
    }
    
    // Ensure shared still uses the default private init
    // static let shared = AudioTranscriptionManager() // This line should effectively use the private init()

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
                return "Loading transcription model..."
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
    
    // Private init is now for the singleton, public/internal init for testability
    // func startProcessing(url: URL, modelContext: ModelContext, whisperState: WhisperState) { ... }
    // is already defined below, no need to redefine.

    func startProcessing(url: URL, modelContext: ModelContext, whisperState: WhisperState) {
        // Cancel any existing processing
        cancelProcessing()
        
        isProcessing = true
        processingPhase = .loading
        messageLog = ""
        errorMessage = nil
        
        currentTask = Task {
            do {
                // Get audio duration early for both paths
                let audioAsset = AVURLAsset(url: url)
                let duration = CMTimeGetSeconds(try await audioAsset.load(.duration))

                // Create permanent copy of the audio file early for both paths
                let recordingsDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("com.prakashjoshipax.VoiceInk")
                    .appendingPathComponent("Recordings")
                
                let fileName = "transcribed_\(UUID().uuidString).wav"
                let permanentURL = recordingsDirectory.appendingPathComponent(fileName)
                
                try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: url, to: permanentURL)

                if useCloudService {
                    processingPhase = .transcribing // Or a new phase e.g., .cloudTranscribing
                    logger.info("Using cloud transcription service for \(url.lastPathComponent)")
                    messageLog += "Using cloud transcription service...\n"

                    let apiKey = UserDefaults.standard.string(forKey: "cloudTranscriptionAPIKey") ?? ""

                    if apiKey.isEmpty {
                        self.errorMessage = "Cloud API key is missing. Please configure it in Settings."
                        logger.error(Logger.Message(stringLiteral: self.errorMessage!))
                        messageLog += "\(self.errorMessage!)\n"
                        // Ensure isProcessing is false and phase is idle before finishing.
                        // handleError will do this, or we can set them manually and call finishProcessing.
                        // Using a more direct approach here:
                        self.isProcessing = false
                        self.processingPhase = .idle
                        await finishProcessing()
                        return
                    }

                    let cloudText = try await self.cloudService.transcribe(audioURL: permanentURL, apiKey: apiKey)

                    let transcription = Transcription(
                        text: cloudText,
                        duration: duration, // Calculated earlier
                        audioFileURL: permanentURL.absoluteString
                    )
                    modelContext.insert(transcription)
                    try modelContext.save()
                    currentTranscription = transcription

                    processingPhase = .completed
                    try? await Task.sleep(nanoseconds: 1_500_000_000) // Keep existing delay for UI
                    await finishProcessing()
                    return // Important: Exit after cloud processing
                }

                // Existing local Whisper model processing logic
                guard let currentModel = whisperState.currentModel else {
                    throw TranscriptionError.noModelSelected
                }
                
                // Load Whisper model
                whisperContext = try await WhisperContext.createContext(path: currentModel.url.path)

                // Process audio file
                processingPhase = .processingAudio
                let samples = try await audioProcessor.processAudioToSamples(url) // Original URL for samples

                // Transcribe
                processingPhase = .transcribing
                await whisperContext?.setPrompt(whisperState.whisperPrompt.transcriptionPrompt)
                try await whisperContext?.fullTranscribe(samples: samples)
                var text = await whisperContext?.getTranscription() ?? ""
                text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                text = WhisperTextFormatter.format(text)
                
                // Apply word replacements if enabled
                if UserDefaults.standard.bool(forKey: "IsWordReplacementEnabled") {
                    text = WordReplacementService.shared.applyReplacements(to: text)
                }
                
                // Handle enhancement if enabled
                if let enhancementService = whisperState.enhancementService,
                   enhancementService.isEnhancementEnabled,
                   enhancementService.isConfigured {
                    processingPhase = .enhancing
                    do {
                        let enhancedText = try await enhancementService.enhance(text)
                        let transcription = Transcription(
                            text: text,
                            duration: duration, // Calculated earlier
                            enhancedText: enhancedText,
                            audioFileURL: permanentURL.absoluteString
                        )
                        modelContext.insert(transcription)
                        try modelContext.save()
                        currentTranscription = transcription
                    } catch {
                        logger.error("Enhancement failed: \(error.localizedDescription)")
                        messageLog += "Enhancement failed: \(error.localizedDescription). Using original transcription.\n"
                        let transcription = Transcription(
                            text: text,
                            duration: duration, // Calculated earlier
                            audioFileURL: permanentURL.absoluteString
                        )
                        modelContext.insert(transcription)
                        try modelContext.save()
                        currentTranscription = transcription
                    }
                } else {
                    let transcription = Transcription(
                        text: text,
                        duration: duration, // Calculated earlier
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
        whisperContext = nil
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
