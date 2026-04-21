import Foundation
import SwiftData
import LLMkit

struct SpeechmaticsProvider: CloudProvider {
    let modelProvider: ModelProvider = .speechmatics
    let providerKey: String = "Speechmatics"
    let languageCodes: [String]? = [
        "ar", "ba", "eu", "be", "bn", "bg", "yue", "ca", "hr", "cs", "da",
        "nl", "en", "et", "fi", "fr", "gl", "de", "el", "he", "hi",
        "hu", "id", "it", "ja", "ko", "lv", "lt", "ms", "mt", "mr",
        "mn", "no", "fa", "pl", "pt", "ro", "ru", "sk", "sl", "es",
        "sw", "sv", "tl", "ta", "th", "tr", "uk", "ur", "vi", "cy",
        "zh"
    ]
    let includesAutoDetect: Bool = true

    var models: [CloudModel] {[
        CloudModel(
            name: "speechmatics-enhanced",
            displayName: "Speechmatics",
            description: "Speechmatics enhanced accuracy transcription with real-time streaming and 50+ language support",
            provider: .speechmatics,
            speed: 0.99,
            accuracy: 0.98,
            isMultilingual: true,
            supportsStreaming: true,
            supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .speechmatics)
        )
    ]}

    func transcribe(audioData: Data, fileName: String, apiKey: String, model: String, language: String?, prompt: String?, customVocabulary: [String]) async throws -> String {
        return try await SpeechmaticsClient.transcribe(
            audioData: audioData,
            fileName: fileName,
            apiKey: apiKey,
            language: language,
            customVocabulary: customVocabulary
        )
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        SpeechmaticsStreamingProvider(modelContext: modelContext)
    }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        return await SpeechmaticsClient.verifyAPIKey(key)
    }
}
