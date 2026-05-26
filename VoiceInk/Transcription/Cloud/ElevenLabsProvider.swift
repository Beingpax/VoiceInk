import Foundation
import SwiftData
import LLMkit

struct ElevenLabsProvider: CloudProvider {
    let modelProvider: ModelProvider = .elevenLabs
    let providerKey: String = "ElevenLabs"
    let languageCodes: [String]? = [
        "af", "am", "ar", "as", "az", "be", "bg", "bn", "bs", "ca",
        "cs", "cy", "da", "de", "el", "en", "es", "et", "eu", "fa",
        "fi", "fil", "fr", "ga", "gl", "gu", "ha", "he", "hi", "hr",
        "hu", "hy", "id", "ig", "is", "it", "ja", "jw", "ka", "kk",
        "km", "kn", "ko", "ku", "ky", "lb", "ln", "lo", "lt", "lv",
        "mi", "mk", "ml", "mn", "mr", "ms", "mt", "my", "ne", "nl",
        "no", "or", "pa", "pl", "ps", "pt", "ro", "ru", "sd", "sk",
        "sl", "sn", "so", "sr", "sv", "sw", "ta", "tg", "te", "th",
        "tr", "uk", "ur", "uz", "vi", "wo", "xh", "yo", "yue", "zh", "zu"
    ]
    let includesAutoDetect: Bool = true

    var models: [CloudModel] {[
        CloudModel(
            name: "scribe_v1",
            displayName: "Scribe v1 (ElevenLabs)",
            description: "ElevenLabs' Scribe model for fast & accurate transcription",
            provider: .elevenLabs,
            speed: 0.7,
            accuracy: 0.98,
            isMultilingual: true,
            supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .elevenLabs)
        ),
        CloudModel(
            name: "scribe_v2",
            displayName: "Scribe V2 (ElevenLabs)",
            description: "ElevenLabs' Scribe V2 model for the most accurate transcription",
            provider: .elevenLabs,
            speed: 0.99,
            accuracy: 0.98,
            isMultilingual: true,
            supportsStreaming: true,
            supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .elevenLabs)
        )
    ]}

    func transcribe(audioData: Data, fileName: String, apiKey: String, model: String, language: String?, prompt: String?, customVocabulary: [String]) async throws -> String {
        return try await ElevenLabsClient.transcribe(
            audioData: audioData,
            fileName: fileName,
            apiKey: apiKey,
            model: model,
            language: language
        )
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        ElevenLabsStreamingProvider()
    }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        return await ElevenLabsClient.verifyAPIKey(key)
    }
}
