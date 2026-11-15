import Foundation

// Isolate Keychain and unrelated provider metadata; model serialization and HTTP use production code.
final class APIKeyManager {
    static let shared = APIKeyManager()
    func getCustomModelAPIKey(forModelId: UUID) -> String? { nil }
    func saveCustomModelAPIKey(_ key: String, forModelId: UUID) {}
}
enum LanguageDictionary {
    static func forProvider(isMultilingual: Bool, provider: ModelProvider = .whisper) -> [String: String] { [:] }
}
struct TranscriptionRequestContext { let language: String? }
enum CloudTranscriptionError: Error {
    case networkError(Error), apiRequestFailed(statusCode: Int, message: String)
    case noTranscriptionReturned, audioFileNotFound
}
