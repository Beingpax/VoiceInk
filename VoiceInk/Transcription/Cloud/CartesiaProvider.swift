import Foundation
import SwiftData
import LLMkit

struct CartesiaProvider: CloudProvider {
    let modelProvider: ModelProvider = .cartesia
    let providerKey: String = "Cartesia"
    let isStreamingOnly: Bool = true
    let languageCodes: [String]? = [
        "af", "am", "ar", "as", "az", "ba", "be", "bg", "bn", "bo",
        "br", "bs", "ca", "cs", "cy", "da", "de", "el", "en", "es",
        "et", "eu", "fa", "fi", "fo", "fr", "gl", "gu", "ha", "haw",
        "he", "hi", "hr", "ht", "hu", "hy", "id", "is", "it", "ja",
        "jw", "ka", "kk", "km", "kn", "ko", "la", "lb", "ln", "lo",
        "lt", "lv", "mg", "mi", "mk", "ml", "mn", "mr", "ms", "mt",
        "my", "ne", "nl", "nn", "no", "oc", "pa", "pl", "ps", "pt",
        "ro", "ru", "sa", "sd", "si", "sk", "sl", "sn", "so", "sq",
        "sr", "su", "sv", "sw", "ta", "te", "tg", "th", "tk", "tl",
        "tr", "tt", "uk", "ur", "uz", "vi", "yi", "yo", "yue", "zh",
        "zu"
    ]
    let includesAutoDetect: Bool = false

    var models: [CloudModel] {[
        CloudModel(
            name: "ink-whisper",
            displayName: "Ink Whisper (Cartesia)",
            description: "Cartesia's fastest streaming STT model — engineered for real-time voice agents with 90+ language support",
            provider: .cartesia,
            speed: 0.99,
            accuracy: 0.94,
            isMultilingual: true,
            supportsStreaming: true,
            supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .cartesia)
        )
    ]}

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        CartesiaStreamingProvider(modelContext: modelContext)
    }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        return await CartesiaStreamingClient.verifyAPIKey(key)
    }
}
