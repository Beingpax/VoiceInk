import Foundation
import SwiftData
import LLMkit

struct SonioxProvider: CloudProvider {
    let modelProvider: ModelProvider = .soniox
    let providerKey: String = "Soniox"
    let languageCodes: [String]? = [
        "af", "sq", "ar", "az", "eu", "be", "bn", "bs", "bg", "ca",
        "zh", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "gl",
        "de", "el", "gu", "he", "hi", "hu", "id", "it", "ja", "kn",
        "kk", "ko", "lv", "lt", "mk", "ms", "ml", "mr", "no", "fa",
        "pl", "pt", "pa", "ro", "ru", "sr", "sk", "sl", "es", "sw",
        "sv", "tl", "ta", "te", "th", "tr", "uk", "ur", "vi", "cy"
    ]
    let includesAutoDetect: Bool = true

    var models: [CloudModel] {[
        CloudModel(
            name: "stt-async-v4",
            displayName: "Soniox V4",
            description: "Soniox transcription model v4 with human-parity accuracy",
            provider: .soniox,
            speed: 0.99,
            accuracy: 0.98,
            isMultilingual: true,
            supportsStreaming: true,
            supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .soniox)
        )
    ]}

    func transcribe(audioData: Data, fileName: String, apiKey: String, model: String, language: String?, prompt: String?, customVocabulary: [String]) async throws -> String {
        return try await SonioxClient.transcribe(
            audioData: audioData,
            fileName: fileName,
            apiKey: apiKey,
            model: model,
            language: language,
            customVocabulary: customVocabulary,
            baseURL: SonioxRegion.current.restBaseURL
        )
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        SonioxStreamingProvider(modelContext: modelContext)
    }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        return await SonioxClient.verifyAPIKey(key, baseURL: SonioxRegion.current.restBaseURL)
    }
}

enum SonioxRegion: String, CaseIterable, Identifiable {
    case us
    case eu
    case jp

    static let defaultsKey = "SonioxRegion"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .us:
            return "United States"
        case .eu:
            return "European Union"
        case .jp:
            return "Japan"
        }
    }

    var restBaseURL: URL {
        switch self {
        case .us:
            return URL(string: "https://api.soniox.com/v1")!
        case .eu:
            return URL(string: "https://api.eu.soniox.com/v1")!
        case .jp:
            return URL(string: "https://api.jp.soniox.com/v1")!
        }
    }

    var realtimeWebSocketURL: URL {
        switch self {
        case .us:
            return URL(string: "wss://stt-rt.soniox.com/transcribe-websocket")!
        case .eu:
            return URL(string: "wss://stt-rt.eu.soniox.com/transcribe-websocket")!
        case .jp:
            return URL(string: "wss://stt-rt.jp.soniox.com/transcribe-websocket")!
        }
    }

    static var current: SonioxRegion {
        let rawValue = UserDefaults.standard.string(forKey: defaultsKey) ?? SonioxRegion.us.rawValue
        return SonioxRegion(rawValue: rawValue) ?? .us
    }
}
