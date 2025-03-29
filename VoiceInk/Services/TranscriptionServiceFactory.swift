//
//  TranscriptionServiceFactory.swift
//  VoiceInk
//
//  Created by Wing CHAN on 29/3/2025.
//

import Foundation
import os

/// A factory class that creates and manages transcription services
class TranscriptionServiceFactory {
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "TranscriptionServiceFactory")
    
    // Default configuration for cloud service
    private var defaultCloudConfig: [String: Any] = [
        "apiEndpoint": "https://api.openai.com/v1/audio/transcriptions",
        "apiKey": ""
    ]
    
    // MARK: - Public Methods
    
    /// Creates a transcription service based on the specified type and configuration
    /// - Parameters:
    ///   - type: Type of transcription service to create
    ///   - configuration: Configuration parameters for the service
    /// - Returns: A transcription service that conforms to the TranscriptionService protocol
    func createService(type: TranscriptionServiceType, configuration: [String: Any]) async throws -> any TranscriptionService {
        logger.notice("Creating \(type.rawValue) transcription service")
        
        switch type {
        case .local:
            return try await WhisperContext.createService(configuration: configuration)
            
        case .cloud:
            return try await CloudTranscriptionService.createService(configuration: configuration)
        }
    }
    
    /// Creates a local transcription service using the specified model path
    /// - Parameter modelPath: Path to the Whisper model file
    /// - Returns: A WhisperContext service
    func createLocalService(modelPath: String) async throws -> WhisperContext {
        logger.notice("Creating local transcription service with model: \(modelPath)")
        
        let configuration: [String: Any] = ["modelPath": modelPath]
        return try await WhisperContext.createService(configuration: configuration)
    }
    
    /// Creates a cloud transcription service with the specified API key
    /// - Parameters:
    ///   - apiKey: API key for cloud service authentication
    ///   - endpoint: Optional custom API endpoint (uses default if nil)
    /// - Returns: A CloudTranscriptionService
    func createCloudService(apiKey: String, endpoint: String? = nil) async throws -> CloudTranscriptionService {
        var configuration = defaultCloudConfig
        configuration["apiKey"] = apiKey
        
        if let endpoint = endpoint {
            configuration["apiEndpoint"] = endpoint
        }
        
        logger.notice("Creating cloud transcription service with endpoint: \(configuration["apiEndpoint"] as? String ?? "unknown")")
        return try await CloudTranscriptionService.createService(configuration: configuration)
    }
    
    /// Updates the default cloud service configuration
    /// - Parameters:
    ///   - apiEndpoint: API endpoint URL
    ///   - apiKey: API key for authentication
    func updateDefaultCloudConfig(apiEndpoint: String? = nil, apiKey: String? = nil) {
        if let apiEndpoint = apiEndpoint {
            defaultCloudConfig["apiEndpoint"] = apiEndpoint
        }
        
        if let apiKey = apiKey {
            defaultCloudConfig["apiKey"] = apiKey
        }
        
        logger.debug("Updated default cloud configuration")
    }
}
