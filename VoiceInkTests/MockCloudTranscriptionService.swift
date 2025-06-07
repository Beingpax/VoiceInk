import Foundation
@testable import VoiceInk // Use @testable to access internal members if needed, and the protocol

class MockCloudTranscriptionService: CloudTranscriptionServiceProtocol {
    var transcribeCallCount = 0
    var lastAudioURL: URL?
    var lastApiKey: String?

    var mockResult: String = "Mocked cloud transcription result"
    var shouldThrowError: Error?

    func transcribe(audioURL: URL, apiKey: String) async throws -> String {
        transcribeCallCount += 1
        lastAudioURL = audioURL
        lastApiKey = apiKey

        if let error = shouldThrowError {
            throw error
        }

        return mockResult
    }
}
