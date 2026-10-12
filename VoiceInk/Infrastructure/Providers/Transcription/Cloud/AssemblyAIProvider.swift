import Foundation
import LLMkit
import SwiftData

struct AssemblyAIProvider: CloudProvider {
    let modelProvider: ModelProvider = .assemblyAI
    let providerKey: String = "AssemblyAI"
    let languageCodes: [String]? = Languages.universal36Codes
    let includesAutoDetect: Bool = true

    var models: [CloudModel] {
        [
            CloudModel(
                name: "universal-3-6-pro",
                displayName: "Universal-3.6 Pro",
                description: "Flagship realtime transcription across 32 languages. Uses Universal-3.5 Pro or Universal-2 for file transcription.",
                provider: .assemblyAI,
                isMultilingual: true,
                supportsStreaming: true,
                supportedLanguages: Languages.universal36
            ),
            CloudModel(
                name: "universal-3-5-pro",
                displayName: "Universal-3.5 Pro",
                description: "Highest-accuracy multilingual transcription with realtime support.",
                provider: .assemblyAI,
                isMultilingual: true,
                supportsStreaming: true,
                supportedLanguages: Languages.universal35
            ),
            CloudModel(
                name: "universal-2",
                displayName: "Universal-2",
                description: "Balanced multilingual transcription with 90+ language support.",
                provider: .assemblyAI,
                isMultilingual: true,
                supportsStreaming: false,
                supportedLanguages: Languages.universal2
            ),
        ]
    }

    func transcribe(
        audioData: Data, fileName: String, apiKey: String, model: String, language: String?,
        customVocabulary: [String], timeout: TimeInterval
    ) async throws -> String {
        return try await AssemblyAIClient.transcribe(
            audioData: audioData,
            fileName: fileName,
            apiKey: apiKey,
            model: try Self.batchModel(for: model, language: language),
            language: language,
            customVocabulary: customVocabulary,
            maxWaitSeconds: timeout,
            timeout: timeout
        )
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        AssemblyAIStreamingProvider(modelContext: modelContext)
    }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        return await AssemblyAIClient.verifyAPIKey(key)
    }

    // The 3.6 Pro model is streaming-only. Explicitly route recorded audio and
    // streaming failures to a prerecorded model supporting the selected language.
    static func batchModel(for model: String, language: String?) throws -> String {
        guard model == "universal-3-6-pro" else { return model }
        if let language, language != "auto", !language.isEmpty,
           !Languages.universal35Codes.contains(language) {
            guard Languages.universal2Codes.contains(language) else {
                throw LLMKitError.networkError("AssemblyAI supports this language only in realtime. Enable realtime transcription to use it.")
            }
            return "universal-2"
        }
        return "universal-3-5-pro"
    }

    private enum Languages {
        static let universal36Codes = [
            "af", "ar", "yue", "ca", "da", "nl", "en", "et", "fi", "fr", "gl",
            "de", "he", "hi", "it", "ja", "ko", "zh", "mr", "no", "nn", "fa",
            "pt", "ro", "ru", "es", "sv", "tr", "ur", "vi", "xh", "zu",
        ]

        static let universal35Codes = [
            "en", "es", "fr", "de", "it", "pt", "ar", "da", "nl",
            "he", "hi", "ja", "zh", "vi", "fi", "no", "sv", "tr", "ca",
        ]

        static let universal2Codes = [
            "en", "en_au", "en_uk", "en_us", "es", "fr", "de", "it", "pt", "nl",
            "hi", "ja", "zh", "fi", "ko", "pl", "ru", "tr", "uk", "vi", "af",
            "sq", "am", "ar", "hy", "as", "az", "ba", "eu", "be", "bn", "bs",
            "br", "bg", "my", "ca", "hr", "cs", "da", "et", "fo", "gl", "ka",
            "el", "gu", "ht", "ha", "haw", "he", "hu", "is", "id", "jw", "kn",
            "kk", "km", "lo", "la", "lv", "ln", "lt", "lb", "mk", "mg", "ms",
            "ml", "mt", "mi", "mr", "mn", "ne", "no", "nn", "oc", "pa", "ps",
            "fa", "ro", "sa", "sr", "sn", "sd", "si", "sk", "sl", "so", "su",
            "sw", "sv", "tl", "tg", "ta", "tt", "te", "th", "bo",
            "tk", "ur", "uz", "cy", "yi", "yo",
        ]

        static let universal36 = LanguageDictionary.forCodes(universal36Codes, includesAutoDetect: true)
        static let universal35 = LanguageDictionary.forCodes(universal35Codes, includesAutoDetect: true)
        static let universal2 = LanguageDictionary.forCodes(universal2Codes, includesAutoDetect: true)
    }
}
