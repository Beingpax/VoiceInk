import Foundation
import LLMkit
import SwiftData

struct GeminiProvider: CloudProvider {
    let modelProvider: ModelProvider = .gemini
    let providerKey: String = "Gemini"
    let languageCodes: [String]? = nil
    let includesAutoDetect: Bool = false

    var models: [CloudModel] {
        [
            CloudModel(
                name: "gemini-3.5-flash",
                displayName: "Gemini 3.5 Flash",
                description: "Google's current fast model for high-quality transcription",
                provider: .gemini,
                speed: 0.92,
                accuracy: 0.96,
                isMultilingual: true,
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .gemini)
            ),
            CloudModel(
                name: "gemini-3.1-flash-lite",
                displayName: "Gemini 3.1 Flash-Lite",
                description: "Google's efficient model for lightweight transcription tasks",
                provider: .gemini,
                speed: 0.95,
                accuracy: 0.94,
                isMultilingual: true,
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .gemini)
            ),
            CloudModel(
                name: "gemini-3.1-pro-preview",
                displayName: "Gemini 3.1 Pro",
                description: "Google's latest model with enhanced transcription capabilities",
                provider: .gemini,
                speed: 0.75,
                accuracy: 0.97,
                isMultilingual: true,
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .gemini)
            ),
        ]
    }

    func transcribe(
        audioData: Data, fileName: String, apiKey: String, model: String, language: String?, customVocabulary: [String]
    ) async throws -> String {
        return try await GeminiTranscriptionClient.transcribe(
            audioData: audioData,
            apiKey: apiKey,
            model: model
        )
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? { nil }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        return await GeminiTranscriptionClient.verifyAPIKey(key)
    }
}
