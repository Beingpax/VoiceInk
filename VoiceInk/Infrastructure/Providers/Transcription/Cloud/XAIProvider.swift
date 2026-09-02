import Foundation
import LLMkit
import SwiftData

struct XAIProvider: CloudProvider {
    let modelProvider: ModelProvider = .xai
    let providerKey: String = "xAI"
    let languageCodes: [String]? = [
        "ar", "cs", "da", "nl", "en", "fil", "fr", "de", "hi", "id",
        "it", "ja", "ko", "mk", "ms", "fa", "pl", "pt", "ro", "ru",
        "es", "sv", "th", "tr", "vi",
    ]
    let includesAutoDetect: Bool = true

    var models: [CloudModel] {
        [
            CloudModel(
                name: "grok-stt",
                displayName: "Grok",
                description: "xAI's Grok speech-to-text with real-time streaming and batch transcription",
                provider: .xai,
                isMultilingual: true,
                supportsStreaming: true,
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .xai)
            )
        ]
    }

    func transcribe(
        audioData: Data, fileName: String, apiKey: String, model: String, language: String?,
        customVocabulary: [String], timeout: TimeInterval
    ) async throws -> String {
        return try await XAIClient.transcribe(
            audioData: audioData,
            fileName: fileName,
            apiKey: apiKey,
            language: language,
            format: true,
            timeout: timeout
        )
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        XAIStreamingProvider()
    }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        return await XAIClient.verifyAPIKey(key)
    }
}
