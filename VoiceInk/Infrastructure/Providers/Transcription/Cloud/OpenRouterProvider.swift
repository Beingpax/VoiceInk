import CryptoKit
import Foundation
import LLMkit
import SwiftData

/// Shared persistence for OpenRouter's separate text and speech-to-text catalogs.
final class OpenRouterCatalogStore: @unchecked Sendable {
    enum Kind: String {
        case enhancement = "openRouterModelCatalog"
        case transcription = "openRouterTranscriptionModelCatalog"
    }

    static let shared = OpenRouterCatalogStore()

    private let lock = NSLock()
    private let defaults = UserDefaults.standard
    private var catalogs: [Kind: [OpenRouterModel]] = [:]

    private init() {
        for kind in [Kind.enhancement, .transcription] {
            guard let data = defaults.data(forKey: kind.rawValue),
                let models = try? JSONDecoder().decode([OpenRouterModel].self, from: data)
            else { continue }
            catalogs[kind] = models
        }
    }

    func models(for kind: Kind) -> [OpenRouterModel]? {
        lock.lock()
        defer { lock.unlock() }
        return catalogs[kind]
    }

    func save(_ models: [OpenRouterModel], for kind: Kind) throws {
        let data = try JSONEncoder().encode(models)
        defaults.set(data, forKey: kind.rawValue)
        lock.lock()
        catalogs[kind] = models
        lock.unlock()
    }

    var legacyEnhancementModelIDs: [String] {
        defaults.array(forKey: "openRouterModels") as? [String] ?? []
    }

    func saveLegacyEnhancementModelIDs(_ ids: [String]) {
        defaults.set(ids, forKey: "openRouterModels")
    }
}

enum OpenRouterTranscriptionCatalog {
    static var models: [OpenRouterModel] {
        OpenRouterCatalogStore.shared.models(for: .transcription) ?? []
    }

    @MainActor
    static func refresh() async throws {
        let catalog = try await OpenRouterClient.fetchTranscriptionModelCatalog()
        guard !catalog.isEmpty else { throw LLMKitError.noResultReturned }
        try OpenRouterCatalogStore.shared.save(catalog, for: .transcription)
    }
}

struct OpenRouterProvider: CloudProvider {
    let modelProvider: ModelProvider = .openRouter
    let providerKey = "OpenRouter"
    let languageCodes: [String]? = ["auto"]
    let includesAutoDetect = true

    var models: [CloudModel] {
        OpenRouterTranscriptionCatalog.models.map { model in
            CloudModel(
                id: stableID(for: model.id),
                name: model.id,
                displayName: model.name ?? model.id,
                description: String(localized: "OpenRouter speech-to-text model"),
                provider: .openRouter,
                isMultilingual: true,
                supportedLanguages: ["auto": String(localized: "Auto-detect")]
            )
        }
    }

    func transcribe(
        audioData: Data, fileName: String, apiKey: String, model: String, language: String?,
        customVocabulary: [String], timeout: TimeInterval
    ) async throws -> String {
        try await OpenRouterTranscriptionClient.transcribe(
            audioData: audioData,
            fileName: fileName,
            apiKey: apiKey,
            model: model,
            timeout: timeout
        )
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? { nil }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        await OpenRouterClient.verifyAPIKey(key)
    }

    private func stableID(for slug: String) -> UUID {
        let digest = Array(SHA256.hash(data: Data("OpenRouter:\(slug)".utf8)))
        return UUID(uuid: (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15]
        ))
    }
}
