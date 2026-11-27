import Foundation
import LLMkit

struct AssemblyAIProvider: CloudProvider {
    let modelProvider: ModelProvider = .assemblyAI
    let providerKey: String = "AssemblyAI"
    let languageCodes: [String]? = Languages.realtimeCodes
    let includesAutoDetect: Bool = true

    static let stt37ModelName = "assemblyai-stt-3-7-realtime-agent"

    var models: [CloudModel] {
        [
            CloudModel(
                name: Self.stt37ModelName,
                displayName: "STT-3.7",
                description: "AssemblyAI's newest and most advanced model.",
                provider: .assemblyAI,
                isMultilingual: true,
                supportsStreaming: true,
                supportedLanguages: Languages.realtime,
                recordedOnlyLanguages: Languages.recordedOnly
            ),
            CloudModel(
                name: "universal-3-6-pro",
                displayName: "Universal-3.6 Pro",
                description: "AssemblyAI's flagship model, supporting 32 languages.",
                provider: .assemblyAI,
                isMultilingual: true,
                supportsStreaming: true,
                supportedLanguages: Languages.realtime,
                recordedOnlyLanguages: Languages.recordedOnly
            ),
        ]
    }

    /// Removed models and the model that replaces them.
    static let retiredModelReplacements: [String: String] = [
        "universal-3-5-pro": stt37ModelName,
        "universal-2": stt37ModelName,
    ]

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

    func makeStreamingProvider(vocabulary: RecordingVocabulary) -> (any StreamingTranscriptionProvider)? {
        AssemblyAIStreamingProvider(customVocabulary: vocabulary.terms)
    }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        return await AssemblyAIClient.verifyAPIKey(key)
    }

    // These models are real-time only, so recorded audio uses STT-3.7 or Universal-2.
    private static let streamingOnlyModels: Set<String> = [
        stt37ModelName,
        "universal-3-6-pro",
    ]

    static func batchModel(for model: String, language: String?) throws -> String {
        guard streamingOnlyModels.contains(model) else { return model }
        guard let language, language != "auto", !language.isEmpty else {
            return "assemblyai-stt-3-7"
        }
        if Languages.stt37RecordedCodes.contains(language) {
            return "assemblyai-stt-3-7"
        }
        if Languages.universal2Codes.contains(language) {
            return "universal-2"
        }
        throw LLMKitError.networkError("AssemblyAI does not support this language for recorded audio.")
    }

    private enum Languages {
        // Supported by STT-3.7 and 3.6 Pro in real time.
        static let realtimeCodes = [
            "af", "ar", "yue", "ca", "da", "nl", "en", "et", "fi", "fr", "gl",
            "de", "he", "hi", "it", "ja", "ko", "zh", "mr", "no", "nn", "fa",
            "pt", "ro", "ru", "es", "sv", "tr", "ur", "vi", "xh", "zu",
        ]

        // STT-3.7 also accepts these English variants for recorded audio.
        static let englishVariantCodes = ["en_au", "en_uk", "en_us"]
        static let stt37RecordedCodes = realtimeCodes + englishVariantCodes

        static let universal2Codes = [
            "en", "en_au", "en_uk", "en_us", "es", "fr", "de", "it", "pt", "nl",
            "hi", "ja", "zh", "fi", "ko", "pl", "ru", "tr", "uk", "vi", "af",
            "sq", "am", "ar", "hy", "as", "az", "ba", "eu", "be", "bn", "bs",
            "br", "bg", "my", "ca", "hr", "cs", "da", "et", "fo", "gl", "ka",
            "el", "gu", "ht", "ha", "haw", "he", "hu", "is", "id", "jw", "kn",
            "kk", "km", "lo", "la", "lv", "ln", "lt", "lb", "mk", "mg", "ms",
            "ml", "mt", "mi", "mr", "mn", "ne", "no", "nn", "oc", "pa", "ps",
            "fa", "ro", "sa", "sr", "sn", "sd", "si", "sk", "sl", "so", "su",
            "sw", "sv", "de_ch", "tl", "tg", "ta", "tt", "te", "th", "bo",
            "tk", "ur", "uz", "cy", "yi", "yo",
        ]

        static let universal2OnlyCodes = universal2Codes.filter { !stt37RecordedCodes.contains($0) }

        static let realtime = LanguageDictionary.forCodes(realtimeCodes, includesAutoDetect: true)

        // Shown with real-time off. Universal-2 languages are labeled as such.
        static let recordedOnly = LanguageDictionary.forCodes(englishVariantCodes)
            .merging(
                LanguageDictionary.forCodes(universal2OnlyCodes).mapValues { "\($0) (Universal-2)" }
            ) { current, _ in current }
    }
}
