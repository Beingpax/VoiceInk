import Foundation
import SwiftData
import LLMkit

struct MistralProvider: CloudProvider {
    let modelProvider: ModelProvider = .mistral
    let providerKey: String = "Mistral"
    let languageCodes: [String]? = ["ar", "de", "en", "es", "fr", "hi", "it", "ja", "ko", "nl", "pt", "ru", "zh"]
    let includesAutoDetect: Bool = true

    var models: [CloudModel] {[
        CloudModel(
            name: "voxtral-mini-latest",
            displayName: "Voxtral (Mistral)",
            description: "Mistral's Voxtral model for fast and accurate transcription",
            provider: .mistral,
            speed: 0.99,
            accuracy: 0.98,
            isMultilingual: true,
            supportsStreaming: true,
            supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .mistral)
        )
    ]}

    func transcribe(audioData: Data, fileName: String, apiKey: String, model: String, language: String?, prompt: String?, customVocabulary: [String]) async throws -> String {
        return try await MistralTranscriptionClient.transcribe(
            audioData: audioData,
            fileName: fileName,
            apiKey: apiKey,
            model: model
        )
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        MistralStreamingProvider()
    }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        return await MistralTranscriptionClient.verifyAPIKey(key)
    }
}
