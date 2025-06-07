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
    private var whisperContext: WhisperContext?
    private let audioProcessor = AudioProcessor()
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
    
    func startProcessing(url: URL, modelContext: ModelContext, whisperState: WhisperState, isMeeting: Bool = false) {
        // Cancel any existing processing
        cancelProcessing()
        
        isProcessing = true
        processingPhase = .loading
        messageLog = ""
        errorMessage = nil
        
        currentTask = Task {
            do {
                guard let currentModel = whisperState.currentModel else {
                    throw TranscriptionError.noModelSelected
                }
                
                // Load Whisper model
                whisperContext = try await WhisperContext.createContext(path: currentModel.url.path)
                
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
                try FileManager.default.copyItem(at: url, to: permanentURL)
                
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
                            duration: duration,
                            enhancedText: enhancedText,
                            audioFileURL: permanentURL.absoluteString,
                            isMeeting: isMeeting
                        )
                        modelContext.insert(transcription)
                        try modelContext.save()
                        currentTranscription = transcription
                    } catch {
                        logger.error("Enhancement failed: \(error.localizedDescription)")
                        messageLog += "Enhancement failed: \(error.localizedDescription). Using original transcription.\n"
                        let transcription = Transcription(
                            text: text,
                            duration: duration,
                            audioFileURL: permanentURL.absoluteString,
                            isMeeting: isMeeting
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
                        isMeeting: isMeeting
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
