import Foundation
import LLMkit
import SwiftData

struct AssemblyAIProvider: CloudProvider {
    let modelProvider: ModelProvider = .assemblyAI
    let providerKey: String = "AssemblyAI"
    let languageCodes: [String]? = Languages.universal35Codes
    let includesAutoDetect: Bool = true

    var models: [CloudModel] {
        [
            CloudModel(
                name: "universal-3-5-pro",
                displayName: "Universal-3.5 Pro",
                description: "Highest-accuracy multilingual transcription with realtime support.",
                provider: .assemblyAI,
                speed: 0.94,
                accuracy: 0.98,
                isMultilingual: true,
                supportsStreaming: true,
                supportedLanguages: Languages.universal35
            ),
            CloudModel(
                name: "universal-2",
                displayName: "Universal-2",
                description: "Balanced multilingual transcription with 90+ language support.",
                provider: .assemblyAI,
                speed: 0.90,
                accuracy: 0.92,
                isMultilingual: true,
                supportsStreaming: false,
                supportedLanguages: Languages.universal2
            ),
        ]
    }

    func transcribe(
        audioData: Data, fileName: String, apiKey: String, model: String, language: String?, customVocabulary: [String]
    ) async throws -> String {
        return try await AssemblyAIClient.transcribe(
            audioData: audioData,
            fileName: fileName,
            apiKey: apiKey,
            model: model,
            language: language,
            customVocabulary: customVocabulary
        )
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        AssemblyAIStreamingProvider(modelContext: modelContext)
    }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        return await AssemblyAIClient.verifyAPIKey(key)
    }

    private enum Languages {
        static let universal35Codes = [
            "en", "es", "fr", "de", "it", "pt", "ar", "da", "nl",
            "he", "hi", "ja", "zh", "vi", "fi", "no", "sv", "tr",
        ]

        private static let universal2Codes = [
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

        static let universal35 = LanguageDictionary.forCodes(universal35Codes, includesAutoDetect: true)
        static let universal2 = LanguageDictionary.forCodes(universal2Codes, includesAutoDetect: true)
    }
}
