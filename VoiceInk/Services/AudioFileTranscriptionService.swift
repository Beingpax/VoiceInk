import Foundation
import SwiftUI
import AVFoundation
import SwiftData
import os

@MainActor
class AudioTranscriptionService: ObservableObject {
    @Published var isTranscribing = false
    @Published var messageLog = ""
    @Published var currentError: TranscriptionError?
    
    private let modelContext: ModelContext
    private let enhancementService: AIEnhancementService?
    private let whisperState: WhisperState
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "AudioTranscriptionService")
    
    // Transcription services
    private let localTranscriptionService: LocalTranscriptionService
    private lazy var cloudTranscriptionService = CloudTranscriptionService()
    private lazy var nativeAppleTranscriptionService = NativeAppleTranscriptionService()
    
    enum TranscriptionError: Error {
        case noAudioFile
        case transcriptionFailed
        case modelNotLoaded
        case invalidAudioFormat
    }
    
    init(modelContext: ModelContext, whisperState: WhisperState) {
        self.modelContext = modelContext
        self.whisperState = whisperState
        self.enhancementService = whisperState.enhancementService
        self.localTranscriptionService = LocalTranscriptionService(modelsDirectory: whisperState.modelsDirectory, whisperState: whisperState)
    }
    
    func retranscribeAudio(from url: URL, using model: any TranscriptionModel) async throws -> Transcription {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TranscriptionError.noAudioFile
        }
        
        await MainActor.run {
            isTranscribing = true
            messageLog = "Starting retranscription...\n"
        }
        
        do {
            // Delegate transcription to appropriate service
            var text: String
            
            switch model.provider {
            case .local:
                messageLog += "Using local transcription service...\n"
                text = try await localTranscriptionService.transcribe(audioURL: url, model: model)
                messageLog += "Local transcription completed.\n"
            case .nativeApple:
                messageLog += "Using Native Apple transcription service...\n"
                text = try await nativeAppleTranscriptionService.transcribe(audioURL: url, model: model)
                messageLog += "Native Apple transcription completed.\n"
            case .parakeetTDT:
                messageLog += "Using Parakeet TDT v2 transcription service...\n"
                // Use the shared Parakeet service from WhisperState to avoid multiple instances
                guard let parakeetService = whisperState.getParakeetService() else {
                    throw TranscriptionError.transcriptionFailed
                }
                text = try await parakeetService.transcribe(audioURL: url, model: model)
                messageLog += "Parakeet transcription completed.\n"
            default: // Cloud models
                messageLog += "Using cloud transcription service...\n"
                text = try await cloudTranscriptionService.transcribe(audioURL: url, model: model)
                messageLog += "Cloud transcription completed.\n"
            }
            
            // Common post-processing for both local and cloud transcriptions
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Apply word replacements if enabled
            if UserDefaults.standard.bool(forKey: "IsWordReplacementEnabled") {
                text = WordReplacementService.shared.applyReplacements(to: text)
                messageLog += "Word replacements applied.\n"
                logger.notice("✅ Word replacements applied")
            }
            
            // Get audio duration
            let audioAsset = AVURLAsset(url: url)
            let duration = CMTimeGetSeconds(try await audioAsset.load(.duration))
            
            // Create a permanent copy of the audio file
            let recordingsDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("com.prakashjoshipax.VoiceInk")
                .appendingPathComponent("Recordings")
            
            let fileName = "retranscribed_\(UUID().uuidString).wav"
            let permanentURL = recordingsDirectory.appendingPathComponent(fileName)
            
            do {
                try FileManager.default.copyItem(at: url, to: permanentURL)
            } catch {
                logger.error("❌ Failed to create permanent copy of audio: \(error.localizedDescription)")
                messageLog += "Failed to create permanent copy of audio: \(error.localizedDescription)\n"
                isTranscribing = false
                throw error
            }
            
            let permanentURLString = permanentURL.absoluteString
            
            // Apply AI enhancement if enabled
            if let enhancementService = enhancementService,
               enhancementService.isEnhancementEnabled,
               enhancementService.isConfigured {
                do {
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
                    do {
                        try modelContext.save()
                    } catch {
                        logger.error("❌ Failed to save transcription: \(error.localizedDescription)")
                        messageLog += "Failed to save transcription: \(error.localizedDescription)\n"
                    }
                    
                    await MainActor.run {
                        isTranscribing = false
                        messageLog += "Done: \(enhancedText)\n"
                    }
                    
                    return newTranscription
                } catch {
                    messageLog += "Enhancement failed: \(error.localizedDescription). Using original transcription.\n"
                    let newTranscription = Transcription(
                        text: text,
                        duration: duration,
                        audioFileURL: permanentURLString
                    )
                    modelContext.insert(newTranscription)
                    do {
                        try modelContext.save()
                    } catch {
                        logger.error("❌ Failed to save transcription: \(error.localizedDescription)")
                        messageLog += "Failed to save transcription: \(error.localizedDescription)\n"
                    }
                    
                    await MainActor.run {
                        isTranscribing = false
                        messageLog += "Done: \(text)\n"
                    }
                    
                    return newTranscription
                }
            } else {
                let newTranscription = Transcription(
                    text: text,
                    duration: duration,
                    audioFileURL: permanentURLString
                )
                modelContext.insert(newTranscription)
                do {
                    try modelContext.save()
                } catch {
                    logger.error("❌ Failed to save transcription: \(error.localizedDescription)")
                    messageLog += "Failed to save transcription: \(error.localizedDescription)\n"
                }
                
                await MainActor.run {
                    isTranscribing = false
                    messageLog += "Done: \(text)\n"
                }
                
                return newTranscription
            }
        } catch {
            logger.error("❌ Transcription failed: \(error.localizedDescription)")
            messageLog += "Transcription failed: \(error.localizedDescription)\n"
            currentError = .transcriptionFailed
            isTranscribing = false
            throw error
        }
    }
}
