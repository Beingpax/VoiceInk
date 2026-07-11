import Foundation
import LLMkit
import SwiftData

struct CartesiaProvider: CloudProvider {
    let modelProvider: ModelProvider = .cartesia
    let providerKey: String = "Cartesia"
    let isStreamingOnly: Bool = true
    let languageCodes: [String]? = ["en"]
    let includesAutoDetect: Bool = false

    var models: [CloudModel] {
        [
            CloudModel(
                name: "ink-2",
                displayName: "Ink 2",
                description: "Cartesia's fastest streaming speech to text model. With English only support.",
                provider: .cartesia,
                speed: 0.99,
                accuracy: 0.98,
                isMultilingual: false,
                supportsStreaming: true,
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: false, provider: .cartesia)
            )
        ]
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        CartesiaStreamingProvider(modelContext: modelContext)
    }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        return await CartesiaStreamingClient.verifyAPIKey(key)
    }
}
