import Foundation
import SwiftData
import LLMkit

struct AssemblyAIProvider: CloudProvider {
    let modelProvider: ModelProvider = .assemblyAI
    let providerKey: String = "AssemblyAI"
    let languageCodes: [String]? = ["en", "es", "de", "fr", "pt", "it"]
    let includesAutoDetect: Bool = true

    var models: [CloudModel] {[
        CloudModel(
            name: "universal-3-pro",
            displayName: "Universal-3 Pro (AssemblyAI)",
            description: "Highest-accuracy multilingual transcription with realtime support.",
            provider: .assemblyAI,
            speed: 0.94,
            accuracy: 0.98,
            isMultilingual: true,
            supportsStreaming: true,
            supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .assemblyAI)
        ),
        CloudModel(
            name: "universal-streaming",
            displayName: "Universal-2 (AssemblyAI)",
            description: "Balanced multilingual transcription with auto-detect.",
            provider: .assemblyAI,
            speed: 0.96,
            accuracy: 0.92,
            isMultilingual: true,
            supportsStreaming: true,
            supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .assemblyAI)
        )
    ]}

    func transcribe(audioData: Data, fileName: String, apiKey: String, model: String, language: String?, prompt: String?, customVocabulary: [String]) async throws -> String {
        return try await AssemblyAIClient.transcribe(
            audioData: audioData,
            fileName: fileName,
            apiKey: apiKey,
            model: model,
            language: language,
            prompt: prompt,
            customVocabulary: customVocabulary
        )
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        AssemblyAIStreamingProvider(modelContext: modelContext)
    }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        return await AssemblyAIClient.verifyAPIKey(key)
    }
}
