import Foundation
import LLMkit

struct MistralProvider: CloudProvider {
    let modelProvider: ModelProvider = .mistral
    let providerKey: String = "Mistral"
    let languageCodes: [String]? = Languages.fileCodes
    let includesAutoDetect: Bool = true

    var models: [CloudModel] {
        [
            CloudModel(
                name: "voxtral-small-transcribe-3-0",
                displayName: "Voxtral Small Transcribe 3",
                description: "Mistral's highest-accuracy Voxtral 3 file transcription model. Public preview.",
                provider: .mistral,
                isMultilingual: true,
                supportedLanguages: Languages.file
            ),
            CloudModel(
                name: "voxtral-mini-transcribe-3-0",
                displayName: "Voxtral Mini Transcribe 3",
                description: "Efficient Voxtral 3 file transcription at a lower cost. Public preview.",
                provider: .mistral,
                isMultilingual: true,
                supportedLanguages: Languages.file
            ),
            CloudModel(
                name: "voxtral-mini-transcribe-realtime-3-0",
                displayName: "Voxtral Mini Transcribe Realtime 3",
                description: "Live Voxtral 3 transcription. Uses Mini Transcribe 3 for files and recovery. Public preview.",
                provider: .mistral,
                isMultilingual: true,
                supportsStreaming: true,
                supportedLanguages: Languages.realtime
            )
        ]
    }

    func transcribe(
        audioData: Data, fileName: String, apiKey: String, model: String, language: String?,
        customVocabulary: [String], timeout: TimeInterval
    ) async throws -> String {
        return try await MistralTranscriptionClient.transcribe(
            audioData: audioData,
            fileName: fileName,
            apiKey: apiKey,
            model: model == "voxtral-mini-transcribe-realtime-3-0" ? "voxtral-mini-transcribe-3-0" : model,
            language: language,
            customVocabulary: customVocabulary,
            timeout: timeout
        )
    }

    @MainActor
    func makeStreamingProvider(vocabulary: RecordingVocabulary) -> (any StreamingTranscriptionProvider)? {
        MistralStreamingProvider(customVocabulary: vocabulary.terms)
    }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        return await MistralTranscriptionClient.verifyAPIKey(key)
    }

    private enum Languages {
        // Documented languages: https://mistral.ai/news/voxtral-3/
        // Filipino uses the API code "tl".
        static let fileCodes = [
            "ar", "bn", "bg", "ca", "zh", "hr", "cs", "da", "nl", "en",
            "et", "fi", "fr", "de", "el", "gu", "hi", "hu", "is", "id",
            "ga", "it", "ja", "kn", "ko", "lv", "lt", "mk", "ms", "ml",
            "mt", "mr", "no", "fa", "pl", "pt", "ro", "ru", "sk", "sl",
            "es", "sv", "tl", "te", "th", "tr", "uk", "vi",
        ]

        static let realtimeCodes = [
            "ar", "bn", "bg", "ca", "zh", "cs", "nl", "en", "et", "fi",
            "fr", "de", "el", "gu", "hi", "id", "it", "ja", "kn", "ko",
            "lv", "mk", "ms", "ml", "mr", "no", "fa", "pl", "pt", "ro",
            "ru", "sk", "es", "tl", "te", "tr",
        ]

        static let file = LanguageDictionary.forCodes(fileCodes, includesAutoDetect: true)
        static let realtime = LanguageDictionary.forCodes(realtimeCodes, includesAutoDetect: true)
    }
}
