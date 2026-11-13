import Foundation
import LLMkit

struct ElevenLabsProvider: CloudProvider {
    enum ScribeModel: String {
        case v3 = "scribe_v3"
        case v2 = "scribe_v2"
        case v2Medical = "scribe_v2_medical"

        var streamingID: String? {
            switch self {
            case .v3: return "scribe_v3_live"
            case .v2: return "scribe_v2_realtime"
            case .v2Medical: return nil
            }
        }
    }

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
        "tr", "uk", "ur", "uz", "vi", "wo", "xh", "yo", "yue", "zh", "zu",
    ]
    let includesAutoDetect: Bool = true

    var models: [CloudModel] {
        [
            CloudModel(
                name: ScribeModel.v3.rawValue,
                displayName: "Scribe V3",
                description: "ElevenLabs' Scribe V3 for recorded audio and Scribe V3 Live for real-time dictation",
                provider: .elevenLabs,
                isMultilingual: true,
                supportsStreaming: ScribeModel.v3.streamingID != nil,
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .elevenLabs)
            ),
            CloudModel(
                name: ScribeModel.v2.rawValue,
                displayName: "Scribe V2",
                description: "ElevenLabs' Scribe V2 for recorded audio and real-time dictation",
                provider: .elevenLabs,
                isMultilingual: true,
                supportsStreaming: ScribeModel.v2.streamingID != nil,
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .elevenLabs)
            ),
            CloudModel(
                name: ScribeModel.v2Medical.rawValue,
                displayName: "Scribe V2 Medical",
                description: "Optimized for clinical audio and medical terminology in 90+ languages. Transcribes after recording stops; no realtime support.",
                provider: .elevenLabs,
                isMultilingual: true,
                supportsStreaming: ScribeModel.v2Medical.streamingID != nil,
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .elevenLabs)
            ),
        ]
    }

    func transcribe(
        audioData: Data, fileName: String, apiKey: String, model: String, language: String?,
        customVocabulary: [String], timeout: TimeInterval
    ) async throws -> String {
        return try await ElevenLabsClient.transcribe(
            audioData: audioData,
            fileName: fileName,
            apiKey: apiKey,
            model: model,
            language: language,
            customVocabulary: customVocabulary,
            timeout: timeout
        )
    }

    func makeStreamingProvider(vocabulary: RecordingVocabulary) -> (any StreamingTranscriptionProvider)? {
        ElevenLabsStreamingProvider(customVocabulary: vocabulary.terms)
    }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        return await ElevenLabsClient.verifyAPIKey(key)
    }
}
