import Foundation

public protocol CloudTranscriptionServiceProtocol {
    func transcribe(audioURL: URL, apiKey: String) async throws -> String
}
