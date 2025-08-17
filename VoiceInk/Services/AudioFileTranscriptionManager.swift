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
    @Published var errorMessage: String?
    
    private var currentTask: Task<Void, Error>?
    private let audioProcessor = AudioProcessor()
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "AudioTranscriptionManager")
    
    // Transcription services - will be initialized when needed
    private var localTranscriptionService: LocalTranscriptionService?
    private lazy var cloudTranscriptionService = CloudTranscriptionService()
    private var parakeetTranscriptionService: ParakeetTranscriptionService?
    
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
    
    private init() {}
    
    func startProcessing(url: URL, modelContext: ModelContext, whisperState: WhisperState) {
        // Cancel any existing processing
        cancelProcessing()
        
        isProcessing = true
        processingPhase = .loading
        errorMessage = nil
        
        currentTask = Task {
            do {
                guard let currentModel = whisperState.currentTranscriptionModel else {
                    throw TranscriptionError.noModelSelected
                }
                
                // Initialize local transcription service if needed
                if localTranscriptionService == nil {
                    localTranscriptionService = LocalTranscriptionService(modelsDirectory: whisperState.modelsDirectory, whisperState: whisperState)
                }
                
                // Initialize parakeet transcription service if needed
                if parakeetTranscriptionService == nil {
                    parakeetTranscriptionService = ParakeetTranscriptionService(customModelsDirectory: whisperState.parakeetModelsDirectory)
                }
                
                // Process audio file
                processingPhase = .processingAudio
                let samples = try await audioProcessor.processAudioToSamples(url)
                
                // Get audio duration
                let audioAsset = AVURLAsset(url: url)
                let duration = CMTimeGetSeconds(try await audioAsset.load(.duration))
                
                // Create permanent copy of the audio file
                let recordingsDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("com.prakashjoshipax.VoiceInk")
                    .appendingPathComponent("Recordings")
                
                let fileName = "transcribed_\(UUID().uuidString).wav"
                let permanentURL = recordingsDirectory.appendingPathComponent(fileName)
                
                try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
                try audioProcessor.saveSamplesAsWav(samples: samples, to: permanentURL)
                
                // Transcribe using appropriate service
                processingPhase = .transcribing
                let transcriptionStart = Date()
                var text: String
                
                switch currentModel.provider {
                case .local:
                    text = try await localTranscriptionService!.transcribe(audioURL: permanentURL, model: currentModel)
                case .parakeet:
                    text = try await parakeetTranscriptionService!.transcribe(audioURL: permanentURL, model: currentModel)
                default: // Cloud models
                    text = try await cloudTranscriptionService.transcribe(audioURL: permanentURL, model: currentModel)
                }
                
                let transcriptionDuration = Date().timeIntervalSince(transcriptionStart)
                text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                
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
                        let (enhancedText, enhancementDuration) = try await enhancementService.enhance(text)
                        let transcription = Transcription(
                            text: text,
                            duration: duration,
                            enhancedText: enhancedText,
                            audioFileURL: permanentURL.absoluteString,
                            transcriptionModelName: currentModel.displayName,
                            aiEnhancementModelName: enhancementService.getAIService()?.currentModel,
                            transcriptionDuration: transcriptionDuration,
                            enhancementDuration: enhancementDuration
                        )
                        modelContext.insert(transcription)
                        try modelContext.save()
                        currentTranscription = transcription
                    } catch {
                        logger.error("Enhancement failed: \(error.localizedDescription)")
                        let transcription = Transcription(
                            text: text,
                            duration: duration,
                            audioFileURL: permanentURL.absoluteString,
                            transcriptionModelName: currentModel.displayName,
                            transcriptionDuration: transcriptionDuration
                        )
                        modelContext.insert(transcription)
                        try modelContext.save()
                        currentTranscription = transcription
                    }
                } else {
                    let transcription = Transcription(
                        text: text,
                        duration: duration,
                        audioFileURL: permanentURL.absoluteString,
                        transcriptionModelName: currentModel.displayName,
                        transcriptionDuration: transcriptionDuration
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
    }
    
    private func finishProcessing() {
        isProcessing = false
        processingPhase = .idle
        currentTask = nil
    }
    
    private func handleError(_ error: Error) {
        logger.error("Transcription error: \(error.localizedDescription)")
        errorMessage = error.localizedDescription
        isProcessing = false
        processingPhase = .idle
        currentTask = nil
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
