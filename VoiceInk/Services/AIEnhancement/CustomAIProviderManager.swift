import Foundation
import os

struct CustomAIProviderConfig: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var baseURL: String
    var models: [String]
    var selectedModel: String

    init(id: UUID = UUID(), name: String, baseURL: String, models: [String], selectedModel: String) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.models = models
        self.selectedModel = selectedModel
    }

    var trimmedModels: [String] {
        models
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var modelName: String {
        let trimmedSelectedModel = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSelectedModel.isEmpty {
            return trimmedSelectedModel
        }
        return trimmedModels.first ?? ""
    }

    var normalizedForStorage: CustomAIProviderConfig {
        let resolvedModelName = self.modelName
        return CustomAIProviderConfig(
            id: id,
            name: name,
            baseURL: baseURL,
            models: resolvedModelName.isEmpty ? [] : [resolvedModelName],
            selectedModel: resolvedModelName
        )
    }
}

final class CustomAIProviderManager: ObservableObject {
    static let shared = CustomAIProviderManager()

    @Published private(set) var providers: [CustomAIProviderConfig] = []

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "CustomAIProviderManager")
    private let providersKey = "customAIProviders"
    private let defaults = UserDefaults.standard

    private init() {
        loadProviders()
        migrateLegacyCustomProviderIfNeeded()
    }

    var availableModelNames: [String] {
        providers.reduce(into: [String]()) { result, provider in
            let modelName = provider.modelName
            guard !modelName.isEmpty,
                  hasAPIKey(for: provider),
                  !result.contains(modelName) else { return }
            result.append(modelName)
        }
    }

    var defaultModelName: String {
        let savedModel = defaults.string(forKey: "customProviderModel")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let configuredModelNames = availableModelNames
        if !savedModel.isEmpty, configuredModelNames.contains(savedModel) {
            return savedModel
        }

        return configuredModelNames.first ?? ""
    }

    var hasConfiguredModels: Bool {
        providers.contains { provider in
            !provider.modelName.isEmpty && hasAPIKey(for: provider)
        }
    }

    @discardableResult
    func addProvider(_ provider: CustomAIProviderConfig, apiKey: String) -> Bool {
        let normalizedProvider = provider.normalizedForStorage
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty,
              APIKeyManager.shared.saveCustomAIProviderAPIKey(trimmedKey, forProviderId: normalizedProvider.id) else {
            return false
        }

        providers.append(normalizedProvider)
        saveProviders()

        return true
    }

    func updateProvider(_ provider: CustomAIProviderConfig) -> Bool {
        let normalizedProvider = provider.normalizedForStorage
        guard let index = providers.firstIndex(where: { $0.id == normalizedProvider.id }) else {
            return false
        }

        let previousModelName = providers[index].modelName
        providers[index] = normalizedProvider
        saveProviders()

        let selectedModelName = defaults.string(forKey: "customProviderModel")
        if selectedModelName == previousModelName || selectedModelName == normalizedProvider.modelName {
            applyRuntimeConfiguration(normalizedProvider)
        }

        return true
    }

    func deleteProvider(_ provider: CustomAIProviderConfig) {
        providers.removeAll { $0.id == provider.id }
        APIKeyManager.shared.deleteCustomAIProviderAPIKey(forProviderId: provider.id)

        if defaults.string(forKey: "customProviderModel") == provider.modelName {
            clearRuntimeConfiguration()
        }

        saveProviders()
    }

    @discardableResult
    func applyConfiguration(forModel modelName: String) -> Bool {
        guard let provider = provider(forModel: modelName) else { return false }
        guard hasAPIKey(for: provider) else { return false }
        applyRuntimeConfiguration(provider)
        return true
    }

    func provider(forModel modelName: String) -> CustomAIProviderConfig? {
        let trimmedModelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModelName.isEmpty else { return nil }

        return providers.first {
            $0.modelName == trimmedModelName || $0.trimmedModels.contains(trimmedModelName)
        }
    }

    func requestConfiguration(forModel modelName: String) -> (baseURL: String, apiKey: String, modelName: String)? {
        guard let provider = provider(forModel: modelName),
              let apiKey = APIKeyManager.shared.getCustomAIProviderAPIKey(forProviderId: provider.id),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return (provider.baseURL, apiKey, provider.modelName)
    }

    func validateProvider(name: String, baseURL: String, model: String, excluding id: UUID? = nil) -> [String] {
        var errors: [String] = []
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedName.isEmpty {
            errors.append("Display name cannot be empty")
        }

        if trimmedURL.isEmpty {
            errors.append("Base URL cannot be empty")
        } else if URL(string: trimmedURL)?.host == nil {
            errors.append("Base URL must be a valid URL")
        }

        if trimmedModel.isEmpty {
            errors.append("Model name cannot be empty")
        }

        if providers.contains(where: { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame && $0.id != id }) {
            errors.append("A custom enhancement model with this display name already exists")
        }

        if providers.contains(where: { $0.modelName.caseInsensitiveCompare(trimmedModel) == .orderedSame && $0.id != id }) {
            errors.append("A custom enhancement model with this model name already exists")
        }

        return errors
    }

    private func loadProviders() {
        guard let data = defaults.data(forKey: providersKey) else { return }
        do {
            providers = try JSONDecoder().decode([CustomAIProviderConfig].self, from: data)
        } catch {
            logger.error("Failed to decode custom AI providers: \(error.localizedDescription, privacy: .public)")
            providers = []
        }
    }

    private func saveProviders() {
        do {
            let data = try JSONEncoder().encode(providers)
            defaults.set(data, forKey: providersKey)
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
        } catch {
            logger.error("Failed to encode custom AI providers: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func hasAPIKey(for provider: CustomAIProviderConfig) -> Bool {
        guard let key = APIKeyManager.shared.getCustomAIProviderAPIKey(forProviderId: provider.id) else {
            return false
        }

        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func migrateLegacyCustomProviderIfNeeded() {
        guard providers.isEmpty,
              let baseURL = defaults.string(forKey: "customProviderBaseURL"),
              !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let model = defaults.string(forKey: "customProviderModel"),
              !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let provider = CustomAIProviderConfig(
            name: "Custom",
            baseURL: baseURL,
            models: [model],
            selectedModel: model
        )
        providers = [provider]

        if let legacyKey = APIKeyManager.shared.getAPIKey(forProvider: AIProvider.custom.rawValue) {
            APIKeyManager.shared.saveCustomAIProviderAPIKey(legacyKey, forProviderId: provider.id)
        }

        saveProviders()
    }

    private func applyRuntimeConfiguration(_ provider: CustomAIProviderConfig) {
        let modelName = provider.modelName

        defaults.set(provider.baseURL, forKey: "customProviderBaseURL")
        defaults.set(modelName, forKey: "customProviderModel")
        defaults.set(modelName, forKey: "\(AIProvider.custom.rawValue)SelectedModel")

        if let key = APIKeyManager.shared.getCustomAIProviderAPIKey(forProviderId: provider.id), !key.isEmpty {
            APIKeyManager.shared.saveAPIKey(key, forProvider: AIProvider.custom.rawValue)
        }

        NotificationCenter.default.post(name: .aiProviderKeyChanged, object: nil)
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }

    private func clearRuntimeConfiguration() {
        defaults.removeObject(forKey: "customProviderBaseURL")
        defaults.removeObject(forKey: "customProviderModel")
        defaults.removeObject(forKey: "\(AIProvider.custom.rawValue)SelectedModel")
        APIKeyManager.shared.deleteAPIKey(forProvider: AIProvider.custom.rawValue)
        NotificationCenter.default.post(name: .aiProviderKeyChanged, object: nil)
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }
}
