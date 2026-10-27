import Foundation
import LLMkit

struct GroqProvider: CloudProvider {
    let modelProvider: ModelProvider = .groq
    let providerKey: String = "Groq"
    let languageCodes: [String]? = nil
    let includesAutoDetect: Bool = false

    var models: [CloudModel] {
        [
            CloudModel(
                name: "whisper-large-v3-turbo",
                displayName: "Whisper Large v3 Turbo",
                description: "Whisper Large v3 Turbo model with Groq's lightning-speed inference",
                provider: .groq,
                isMultilingual: true,
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .groq)
            )
        ]
    }

    func transcribe(
        audioData: Data, fileName: String, apiKey: String, model: String, language: String?,
        customVocabulary: [String], timeout: TimeInterval
    ) async throws -> String {
        return try await OpenAITranscriptionClient.transcribe(
            baseURL: URL(string: "https://api.groq.com/openai")!,
            audioData: audioData,
            fileName: fileName,
            apiKey: apiKey,
            model: model,
            language: language,
            prompt: Self.vocabularyPrompt(from: customVocabulary),
            timeout: timeout
        )
    }

    static func vocabularyPrompt(from terms: [String]) -> String? {
        // Groq rejects prompts over 896 UTF-8 bytes before Whisper can trim tokens.
        let maximumBytes = 896
        var selected: [String] = []
        var byteCount = 0
        for term in terms where !term.isEmpty {
            let requiredBytes = term.utf8.count + (selected.isEmpty ? 0 : 2)
            guard requiredBytes <= maximumBytes - byteCount else { continue }
            selected.append(term)
            byteCount += requiredBytes
        }
        return selected.isEmpty ? nil : selected.joined(separator: ", ")
    }

    func makeStreamingProvider(vocabulary: RecordingVocabulary) -> (any StreamingTranscriptionProvider)? { nil }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        return await OpenAITranscriptionClient.verifyAPIKey(
            baseURL: URL(string: "https://api.groq.com/openai")!,
            apiKey: key
        )
    }
}
