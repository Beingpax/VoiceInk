import Foundation
import LLMkit

struct ZoomScribeProvider: CloudProvider {
    /// Zoom routes support lookups by this prefix. Each request appends a fresh UUID.
    static let trackingIdPrefix = "zoom_ai_community_voiceink_"

    /// UserDefaults key for the add-on Text Polishing option. Off by default.
    static let textPolishingKey = "ZoomScribeTextPolishing"

    static var textPolishingEnabled: Bool {
        UserDefaults.standard.bool(forKey: textPolishingKey)
    }

    /// Text Polishing applies only to the English models. Auto (`nil`, "", "auto") resolves to English for them.
    static func textPolishingAllowed(model: String, language: String?) -> Bool {
        guard model == "zoom-scribe-en" || model == "zoom-scribe-en-pro" else { return false }
        guard let language else { return true }
        let normalized = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["", "auto", "en"].contains(normalized)
    }

    /// The polishing value actually sent to Zoom for a request.
    static func effectiveTextPolishing(model: String, language: String?) -> Bool {
        ZoomScribeRequestOptions.textPolishingRequested && textPolishingAllowed(model: model, language: language)
    }

    private static let supportedLanguageCodes = ["en", "ar", "zh", "fr", "de", "it", "ja", "ko", "pt", "es"]

    let modelProvider: ModelProvider = .zoomScribe
    let providerKey: String = "Zoom Scribe"
    let languageCodes: [String]? = ZoomScribeProvider.supportedLanguageCodes
    let includesAutoDetect: Bool = true

    var models: [CloudModel] {
        [
            CloudModel(
                name: "zoom-scribe-multilingual",
                displayName: "Zoom Scribe Multilingual",
                description: "Zoom Scribe multilingual speech to text with automatic language detection.",
                provider: .zoomScribe,
                isMultilingual: true,
                supportsStreaming: true,
                supportedLanguages: LanguageDictionary.forCodes([], includesAutoDetect: true)
            ),
            CloudModel(
                name: "zoom-scribe-en",
                displayName: "Zoom Scribe",
                description: "Zoom Scribe speech to text. Choose one of 10 languages: English, Arabic, Chinese, French, German, Italian, Japanese, Korean, Portuguese and Spanish.",
                provider: .zoomScribe,
                isMultilingual: true,
                supportsStreaming: true,
                supportedLanguages: LanguageDictionary.forCodes(ZoomScribeProvider.supportedLanguageCodes)
            ),
            CloudModel(
                name: "zoom-scribe-en-pro",
                displayName: "Zoom Scribe English Pro",
                description: "Zoom Scribe high accuracy English speech to text. Requires Zoom Scribe premium model access. Add-on: may incur extra cost. See zoom.ai.",
                provider: .zoomScribe,
                isMultilingual: false,
                supportsStreaming: true,
                supportedLanguages: LanguageDictionary.forCodes(["en"])
            ),
        ]
    }

    func transcribe(
        audioData: Data, fileName: String, apiKey: String, model: String, language: String?,
        customVocabulary: [String], timeout: TimeInterval
    ) async throws -> String {
        do {
            return try await ZoomScribeClient.transcribe(
                audioData: audioData, fileName: fileName, apiKey: apiKey, model: model, language: language,
                customVocabulary: customVocabulary, trackingIdPrefix: Self.trackingIdPrefix, timeout: timeout,
                textPolishing: Self.effectiveTextPolishing(model: model, language: language))
        } catch let error where ZoomScribeProvider.shouldTranscode(after: error) {
            // Fast mode rejected the container or the size. Re-encode once and retry.
            let fileExtension = URL(fileURLWithPath: fileName).pathExtension.lowercased()
            let aacData = try ZoomScribeAudioEncoder.transcodeToAAC(audioData, inputExtension: fileExtension)
            return try await ZoomScribeClient.transcribe(
                audioData: aacData, fileName: "audio.m4a", apiKey: apiKey, model: model, language: language,
                customVocabulary: customVocabulary, trackingIdPrefix: Self.trackingIdPrefix, timeout: timeout,
                textPolishing: Self.effectiveTextPolishing(model: model, language: language))
        }
    }

    @MainActor
    func makeStreamingProvider(vocabulary: RecordingVocabulary) -> (any StreamingTranscriptionProvider)? {
        ZoomScribeStreamingProvider(customVocabulary: vocabulary.terms)
    }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        await ZoomScribeStreamingClient.verifyAPIKey(key, trackingIdPrefix: Self.trackingIdPrefix)
    }

    /// Fast mode answers 415 for an undocumented container and 413 for an oversized body. Re-encoding fixes both.
    static func shouldTranscode(after error: Error) -> Bool {
        guard let llmError = error as? LLMKitError,
              case .httpError(let statusCode, _) = llmError
        else { return false }
        return shouldTranscode(statusCode: statusCode)
    }

    static func shouldTranscode(statusCode: Int) -> Bool {
        statusCode == 413 || statusCode == 415
    }
}
