import Foundation
import SwiftData
import LLMkit

struct GeminiProvider: CloudProvider {
    let modelProvider: ModelProvider = .gemini
    let providerKey: String = "Gemini"
    let languageCodes: [String]? = nil
    let includesAutoDetect: Bool = false

    var models: [CloudModel] {[
        CloudModel(
            name: "gemini-2.5-pro",
            displayName: "Gemini 2.5 Pro",
            description: "Google's advanced model with high-quality transcription capabilities",
            provider: .gemini,
            speed: 0.7,
            accuracy: 0.97,
            isMultilingual: true,
            supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .gemini)
        ),
        CloudModel(
            name: "gemini-2.5-flash",
            displayName: "Gemini 2.5 Flash",
            description: "Google's optimized model for low-latency transcription",
            provider: .gemini,
            speed: 0.9,
            accuracy: 0.95,
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
        CloudModel(
            name: "gemini-3-flash-preview",
            displayName: "Gemini 3 Flash",
            description: "Google's newest fast model combining intelligence with superior speed",
            provider: .gemini,
            speed: 0.92,
            accuracy: 0.95,
            isMultilingual: true,
            supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .gemini)
        )
    ]}

    func transcribe(audioData: Data, fileName: String, apiKey: String, model: String, language: String?, prompt: String?, customVocabulary: [String]) async throws -> String {
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
