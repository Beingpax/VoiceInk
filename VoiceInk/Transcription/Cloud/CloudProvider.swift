import Foundation
import SwiftData

protocol CloudProvider {
    var modelProvider: ModelProvider { get }
    var providerKey: String { get }
    var languageCodes: [String]? { get }
    var includesAutoDetect: Bool { get }
    var models: [CloudModel] { get }
    /// True when the provider has no batch HTTP endpoint and requires streaming for all transcription.
    var isStreamingOnly: Bool { get }

    func transcribe(audioData: Data, fileName: String, apiKey: String, model: String, language: String?, prompt: String?, customVocabulary: [String]) async throws -> String
    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)?
    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?)
}

extension CloudProvider {
    var isStreamingOnly: Bool { false }

    /// Streaming-only providers inherit this and get a clear error if batch is somehow attempted.
    /// Providers that support batch transcription override this with their real implementation.
    func transcribe(audioData: Data, fileName: String, apiKey: String, model: String, language: String?, prompt: String?, customVocabulary: [String]) async throws -> String {
        throw CloudTranscriptionError.unsupportedProvider
    }
}

enum CloudProviderRegistry {
    static let allProviders: [any CloudProvider] = [
        GroqProvider(),
        ElevenLabsProvider(),
        DeepgramProvider(),
        MistralProvider(),
        GeminiProvider(),
        SonioxProvider(),
        SpeechmaticsProvider(),
        AssemblyAIProvider(),
        XAIProvider(),
        CartesiaProvider()
    ]

    static func provider(for modelProvider: ModelProvider) -> (any CloudProvider)? {
        allProviders.first { $0.modelProvider == modelProvider }
    }
}
