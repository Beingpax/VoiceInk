import AVFoundation
import Foundation
import os
import SwiftData
import SwiftUI

@MainActor
class AudioTranscriptionService: ObservableObject {
    @Published var isTranscribing = false
    @Published var messageLog = ""
    @Published var currentError: TranscriptionError?
    
    private var transcriptionService: (any TranscriptionService)?
    private let modelContext: ModelContext
    private let enhancementService: AIEnhancementService?
    private let whisperState: WhisperState
    private let serviceFactory = TranscriptionServiceFactory()
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "AudioTranscriptionService")
    
    enum TranscriptionError: Error {
        case noAudioFile
        case transcriptionFailed
        case modelNotLoaded
        case invalidAudioFormat
        case serviceCreationFailed
    }
    
    init(modelContext: ModelContext, whisperState: WhisperState) {
        self.modelContext = modelContext
        self.whisperState = whisperState
        self.enhancementService = whisperState.enhancementService
    }
    
    func retranscribeAudio(from url: URL, using whisperModel: WhisperModel) async throws -> Transcription {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TranscriptionError.noAudioFile
        }
        
        defer {
            if let service = transcriptionService {
                Task {
                    await service.releaseResources()
                    transcriptionService = nil
                }
            }
        }
        
        await MainActor.run {
            isTranscribing = true
            messageLog = "Loading transcription service...\n"
        }
        
        // Use whisperState's selected service type
        let serviceType = whisperState.transcriptionServiceType
        
        // Create appropriate transcription service
        if transcriptionService == nil {
            do {
                switch serviceType {
                case .local:
                    messageLog += "Creating local transcription service with model: \(whisperModel.name)\n"
                    let configuration: [String: Any] = ["modelPath": whisperModel.url.path]
                    transcriptionService = try await serviceFactory.createService(type: .local, configuration: configuration)
                    
                case .cloud:
                    messageLog += "Creating cloud transcription service\n"
                    let configuration: [String: Any] = [
                        "apiKey": whisperState.cloudTranscriptionApiKey,
                        "apiEndpoint": whisperState.cloudTranscriptionApiEndpoint,
                        "modelName": whisperState.cloudTranscriptionModelName
                    ]
                    transcriptionService = try await serviceFactory.createService(type: .cloud, configuration: configuration)
                }
                
                messageLog += "Transcription service loaded successfully.\n"
            } catch {
                logger.error("❌ Failed to create transcription service: \(error.localizedDescription)")
                messageLog += "Failed to create transcription service: \(error.localizedDescription)\n"
                isTranscribing = false
                throw TranscriptionError.serviceCreationFailed
            }
        }
        
        guard let transcriptionService = transcriptionService else {
            isTranscribing = false
            throw TranscriptionError.serviceCreationFailed
        }
        
        // Get audio duration
        let audioAsset = AVURLAsset(url: url)
        var duration: TimeInterval = 0
        
        if #available(macOS 13.0, *) {
            let durationValue = try await audioAsset.load(.duration)
            duration = CMTimeGetSeconds(durationValue)
        } else {
            duration = CMTimeGetSeconds(audioAsset.duration)
        }
        
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
        
        // Transcribe the audio
        messageLog += "Transcribing audio...\n"
        
        do {
            let selectedLanguage = switch whisperState.transcriptionServiceType {
            case .local:
                whisperState.selectedLanguage
            case .cloud:
                whisperState.cloudTranscriptionLanguage
            }
            // Set language from WhisperState based on mode
            await transcriptionService.setLanguage(selectedLanguage)
            
            // Process with transcription service - using the same prompt as WhisperState
            messageLog += "Setting prompt: \(whisperState.whisperPrompt.transcriptionPrompt)\n"
            await transcriptionService.setPrompt(whisperState.whisperPrompt.transcriptionPrompt)
            
            // Use direct file URL transcription instead of reading samples
            try await transcriptionService.fullTranscribeFromURL(fileURL: permanentURL)
            
            var text = await transcriptionService.getTranscription()
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            logger.notice("✅ Retranscription completed successfully, length: \(text.count) characters")
            
            // Apply word replacements if enabled
            if UserDefaults.standard.isWordReplacementEnabled {
                text = WordReplacementService.shared.applyReplacements(to: text)
                logger.notice("✅ Word replacements applied")
            }
            
            // Apply AI enhancement if enabled - using the same enhancement service as WhisperState
            if let enhancementService = enhancementService,
               enhancementService.isEnhancementEnabled,
               enhancementService.isConfigured
            {
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
