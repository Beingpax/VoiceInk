//
//  TranscriptionService.swift
//  VoiceInk
//
//  Created by Wing CHAN on 28/3/2025.
//

import Foundation

/// Protocol defining the interface for transcription services
protocol TranscriptionService: Actor {
    /// Transcribes audio directly from a file URL
    /// - Parameter fileURL: The URL of the audio file to transcribe
    func fullTranscribeFromURL(fileURL: URL) async throws
    
    /// Gets the transcription result after processing
    /// - Returns: The transcribed text
    func getTranscription() -> String
    
    /// Sets a prompt to guide the transcription process
    /// - Parameter prompt: Optional prompt string
    func setPrompt(_ prompt: String?)
    
    /// Releases any resources held by the service
    func releaseResources()
    
    /// Creates a new instance of the service with the provided configuration
    /// - Parameter configuration: Dictionary containing configuration parameters
    /// - Returns: An initialized transcription service
    static func createService(configuration: [String: Any]) async throws -> Self
    
    /// Set language for transcription
    /// - Parameter language: Language code, https://platform.openai.com/docs/guides/speech-to-text#supported-languages
    func setLanguage(_ language: String?)
}

/// Enum defining the type of transcription service
enum TranscriptionServiceType: String, CaseIterable, Identifiable {
    case local = "Local"
    case cloud = "Cloud"
    
    var id: String { self.rawValue }
    
    var description: String {
        switch self {
        case .local:
            return "Local Transcription (Whisper)"
        case .cloud:
            return "Cloud Transcription"
        }
    }
}
