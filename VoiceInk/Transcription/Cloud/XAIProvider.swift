import Foundation
import SwiftData
import LLMkit

struct XAIProvider: CloudProvider {
    let modelProvider: ModelProvider = .xai
    let providerKey: String = "xAI"
    let languageCodes: [String]? = [
        "ar", "cs", "da", "nl", "en", "fil", "fr", "de", "hi", "id",
        "it", "ja", "ko", "mk", "ms", "fa", "pl", "pt", "ro", "ru",
        "es", "sv", "th", "tr", "vi"
    ]
    let includesAutoDetect: Bool = true

    var models: [CloudModel] {[
        CloudModel(
            name: "grok-stt",
            displayName: "Grok (xAI)",
            description: "xAI's Grok speech-to-text with real-time streaming and batch transcription",
            provider: .xai,
            speed: 0.99,
            accuracy: 0.98,
            isMultilingual: true,
            supportsStreaming: true,
            supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .xai)
        )
    ]}

    func transcribe(audioData: Data, fileName: String, apiKey: String, model: String, language: String?, prompt: String?, customVocabulary: [String]) async throws -> String {
        return try await XAIClient.transcribe(
            audioData: audioData,
            fileName: fileName,
            apiKey: apiKey,
            language: language,
            format: true
        )
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        XAIStreamingProvider()
    }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        return await XAIClient.verifyAPIKey(key)
    }
}
