import Foundation
@testable import VoiceInk

/// Mock transcription service for testing
@available(macOS 14.0, *)
final class MockTranscriptionService: TranscriptionService {
    
    // MARK: - Configuration
    
    var shouldSucceed: Bool = true
    var transcriptionDelay: TimeInterval = 0.1
    var mockTranscriptionText: String = "Mock transcription text"
    var mockError: Error?
    
    // MARK: - Call Tracking
    
    private(set) var transcribeCalls: [(audioURL: URL, model: any TranscriptionModel)] = []
    private(set) var transcribeCallCount: Int = 0
    
    // MARK: - TranscriptionService
    
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        transcribeCalls.append((audioURL, model))
        transcribeCallCount += 1
        
        // Simulate processing delay
        if transcriptionDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(transcriptionDelay * 1_000_000_000))
        }
        
        // Check for cancellation
        try Task.checkCancellation()
        
        // Simulate failure if configured
        if !shouldSucceed, let error = mockError {
            throw error
        }
        
        // Return mock transcription
        return mockTranscriptionText
    }
    
    // MARK: - Test Helpers
    
    func reset() {
        transcribeCalls.removeAll()
        transcribeCallCount = 0
        shouldSucceed = true
        transcriptionDelay = 0.1
        mockTranscriptionText = "Mock transcription text"
        mockError = nil
    }
    
    func wasCalledWith(audioURL: URL) -> Bool {
        return transcribeCalls.contains { $0.audioURL == audioURL }
    }
    
    func wasCalledWith(modelName: String) -> Bool {
        return transcribeCalls.contains { $0.model.name == modelName }
    }
}

/// Mock cloud transcription service
@available(macOS 14.0, *)
final class MockCloudTranscriptionService: TranscriptionService {
    var shouldFail: Bool = false
    var errorToThrow: Error?
    var transcriptionResult: String = "Cloud transcription result"
    var networkDelay: TimeInterval = 0.2
    
    private(set) var callCount: Int = 0
    
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        callCount += 1
        
        // Simulate network delay
        try await Task.sleep(nanoseconds: UInt64(networkDelay * 1_000_000_000))
        
        if shouldFail {
            throw errorToThrow ?? MockError.transcriptionFailed
        }
        
        return transcriptionResult
    }
    
    func reset() {
        shouldFail = false
        errorToThrow = nil
        transcriptionResult = "Cloud transcription result"
        networkDelay = 0.2
        callCount = 0
    }
}

/// Mock local transcription service
@available(macOS 14.0, *)
final class MockLocalTranscriptionService: TranscriptionService {
    var isModelLoaded: Bool = false
    var transcriptionText: String = "Local transcription"
    var shouldSimulateModelLoadFailure: Bool = false
    
    private(set) var modelLoadAttempts: Int = 0
    private(set) var transcriptionAttempts: Int = 0
    
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        transcriptionAttempts += 1
        
        if shouldSimulateModelLoadFailure {
            throw MockError.modelLoadFailed
        }
        
        if !isModelLoaded {
            await loadModel()
        }
        
        // Simulate processing
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        
        return transcriptionText
    }
    
    private func loadModel() async {
        modelLoadAttempts += 1
        isModelLoaded = true
    }
    
    func unloadModel() {
        isModelLoaded = false
    }
}

// MARK: - Mock Errors

enum MockError: Error, LocalizedError {
    case transcriptionFailed
    case modelLoadFailed
    case networkError
    case invalidAPIKey
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .transcriptionFailed:
            return "Mock transcription failed"
        case .modelLoadFailed:
            return "Mock model load failed"
        case .networkError:
            return "Mock network error"
        case .invalidAPIKey:
            return "Mock invalid API key"
        case .timeout:
            return "Mock timeout"
        }
    }
}
