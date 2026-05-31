import Foundation

struct AIProviderConfiguration: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var provider: AIProvider
    var model: String
    var customBaseURL: String?
    var customModel: String?
    var isDefault: Bool

    private enum CodingKeys: String, CodingKey {
        case id, name, provider, model, customBaseURL, customModel, isDefault
    }

    init(
        id: UUID = UUID(),
        name: String,
        provider: AIProvider,
        model: String = "",
        customBaseURL: String? = nil,
        customModel: String? = nil,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.model = model.isEmpty ? provider.defaultModel : model
        self.customBaseURL = customBaseURL
        self.customModel = customModel
        self.isDefault = isDefault
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        provider = try container.decode(AIProvider.self, forKey: .provider)
        model = try container.decode(String.self, forKey: .model)
        customBaseURL = try container.decodeIfPresent(String.self, forKey: .customBaseURL)
        customModel = try container.decodeIfPresent(String.self, forKey: .customModel)
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
    }

    var effectiveModel: String {
        if provider == .custom, let custom = customModel, !custom.isEmpty {
            return custom
        }
        return model
    }

    var effectiveBaseURL: String {
        if let custom = customBaseURL, !custom.isEmpty {
            return custom
        }
        return provider.baseURL
    }

    var hasAPIKey: Bool {
        if !provider.requiresAPIKey {
            return true
        }
        return APIKeyManager.shared.hasAPIKey(forProvider: provider.rawValue)
    }
}

struct ResolvedProviderConfig {
    let provider: AIProvider
    let apiKey: String
    let model: String
    let baseURL: String
}
