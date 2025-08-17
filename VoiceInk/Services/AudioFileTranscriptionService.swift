import Foundation
import SwiftUI
import AVFoundation
import SwiftData
import os

@MainActor
class AudioTranscriptionService: ObservableObject {
    @Published var isTranscribing = false
    @Published var currentError: TranscriptionError?
    
    private let modelContext: ModelContext
    private let enhancementService: AIEnhancementService?
    private let whisperState: WhisperState
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "AudioTranscriptionService")
    
    // Transcription services
    private let localTranscriptionService: LocalTranscriptionService
    private lazy var cloudTranscriptionService = CloudTranscriptionService()
    private lazy var parakeetTranscriptionService = ParakeetTranscriptionService(customModelsDirectory: whisperState.parakeetModelsDirectory)
    
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
        }
        
        do {
            // Delegate transcription to appropriate service
            let transcriptionStart = Date()
            var text: String
            
            switch model.provider {
            case .local:
                text = try await localTranscriptionService.transcribe(audioURL: url, model: model)
            case .parakeet:
                text = try await parakeetTranscriptionService.transcribe(audioURL: url, model: model)
            default: // Cloud models
                text = try await cloudTranscriptionService.transcribe(audioURL: url, model: model)
            }
            
            let transcriptionDuration = Date().timeIntervalSince(transcriptionStart)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Apply word replacements if enabled
            if UserDefaults.standard.bool(forKey: "IsWordReplacementEnabled") {
                text = WordReplacementService.shared.applyReplacements(to: text)
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
                isTranscribing = false
                throw error
            }
            
            let permanentURLString = permanentURL.absoluteString
            
            // Apply AI enhancement if enabled
            if let enhancementService = enhancementService,
               enhancementService.isEnhancementEnabled,
               enhancementService.isConfigured {
                do {
                    let (enhancedText, enhancementDuration) = try await enhancementService.enhance(text)
                    
                    let newTranscription = Transcription(
                        text: text,
                        duration: duration,
                        enhancedText: enhancedText,
                        audioFileURL: permanentURLString,
                        transcriptionModelName: model.displayName,
                        aiEnhancementModelName: enhancementService.getAIService()?.currentModel,
                        transcriptionDuration: transcriptionDuration,
                        enhancementDuration: enhancementDuration
                    )
                    modelContext.insert(newTranscription)
                    do {
                        try modelContext.save()
                    } catch {
                        logger.error("❌ Failed to save transcription: \(error.localizedDescription)")
                    }
                    
                    await MainActor.run {
                        isTranscribing = false
                    }
                    
                    return newTranscription
                } catch {
                    let newTranscription = Transcription(
                        text: text,
                        duration: duration,
                        audioFileURL: permanentURLString,
                        transcriptionModelName: model.displayName,
                        transcriptionDuration: transcriptionDuration
                    )
                    modelContext.insert(newTranscription)
                    do {
                        try modelContext.save()
                    } catch {
                        logger.error("❌ Failed to save transcription: \(error.localizedDescription)")
                    }
                    
                    await MainActor.run {
                        isTranscribing = false
                    }
                    
                    return newTranscription
                }
            } else {
                let newTranscription = Transcription(
                    text: text,
                    duration: duration,
                    audioFileURL: permanentURLString,
                    transcriptionModelName: model.displayName,
                    transcriptionDuration: transcriptionDuration
                )
                modelContext.insert(newTranscription)
                do {
                    try modelContext.save()
                } catch {
                    logger.error("❌ Failed to save transcription: \(error.localizedDescription)")
                }
                
                await MainActor.run {
                    isTranscribing = false
                }
                
                return newTranscription
            }
        } catch {
            logger.error("❌ Transcription failed: \(error.localizedDescription)")
            currentError = .transcriptionFailed
            isTranscribing = false
            throw error
        }
    }
}
