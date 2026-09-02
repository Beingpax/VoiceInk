import Foundation
import LLMkit
import SwiftData

struct DeepgramProvider: CloudProvider {
    let modelProvider: ModelProvider = .deepgram
    let providerKey: String = "Deepgram"
    let languageCodes: [String]? = Self.nova3LanguageCodes
    let includesAutoDetect: Bool = true

    /// Nova-3 languages documented by Deepgram for hosted batch and streaming transcription.
    /// `auto` is presented by VoiceInk and translated to Deepgram's `language=multi` mode.
    private static let nova3LanguageCodes = [
        "af", "af-ZA",
        "ar", "ar-AE", "ar-SA", "ar-QA", "ar-KW", "ar-SY", "ar-LB", "ar-PS", "ar-JO", "ar-EG",
        "ar-SD", "ar-TD", "ar-MA", "ar-DZ", "ar-TN", "ar-IQ", "ar-IR",
        "hy", "be", "bn", "bs", "bg", "ca",
        "zh-HK", "zh", "zh-CN", "zh-Hans", "zh-TW", "zh-Hant",
        "hr", "cs", "da", "da-DK", "nl", "en", "en-US", "en-AU", "en-GB", "en-IN", "en-NZ", "et",
        "fi", "nl-BE", "fr", "fr-CA", "ka", "ka-GE", "de", "de-CH",
        "el", "gu", "gu-IN", "he", "hi", "hu", "id", "it", "ja", "kn", "ko", "ko-KR", "lv",
        "lt", "mk", "ms", "mr", "ne", "no", "fa", "pl", "pt", "pt-BR", "pt-PT", "pa", "pa-IN",
        "ro", "ru", "sr", "sk", "sl", "es", "es-419", "sv", "sv-SE", "tl", "ta", "te", "th",
        "th-TH", "tr", "uk", "ur", "vi",
    ]

    private static let nova3MedicalLanguageCodes = [
        "en", "en-US", "en-AU", "en-CA", "en-GB", "en-IE", "en-IN", "en-NZ",
    ]

    private static var nova3SupportedLanguages: [String: String] {
        var languages = LanguageDictionary.forCodes(nova3LanguageCodes)
        languages["auto"] = "Auto"
        return languages
    }

    var models: [CloudModel] {
        [
            CloudModel(
                name: "nova-3",
                displayName: "Nova 3",
                description: "Deepgram's latest Nova 3 model for fast, accurate transcription",
                provider: .deepgram,
                isMultilingual: true,
                supportsStreaming: true,
                supportedLanguages: Self.nova3SupportedLanguages
            ),
            CloudModel(
                name: "nova-3-medical",
                displayName: "Nova 3 Medical",
                description: "Specialized medical transcription model optimized for clinical environments",
                provider: .deepgram,
                isMultilingual: false,
                supportsStreaming: true,
                supportedLanguages: LanguageDictionary.forCodes(Self.nova3MedicalLanguageCodes)
            ),
        ]
    }

    func transcribe(
        audioData: Data, fileName: String, apiKey: String, model: String, language: String?,
        customVocabulary: [String], timeout: TimeInterval
    ) async throws -> String {
        let deepgramLanguage = model == "nova-3" && language == nil ? "multi" : language
        return try await DeepgramClient.transcribe(
            audioData: audioData,
            apiKey: apiKey,
            model: model,
            language: deepgramLanguage,
            customVocabulary: Array(customVocabulary.prefix(100)),
            timeout: timeout
        )
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        DeepgramStreamingProvider(modelContext: modelContext)
    }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        return await DeepgramClient.verifyAPIKey(key)
    }
}
