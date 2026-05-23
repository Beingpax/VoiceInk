import Foundation
import LLMkit
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
}

final class CustomAIProviderManager: ObservableObject {
    static let shared = CustomAIProviderManager()

    @Published private(set) var providers: [CustomAIProviderConfig] = []
    @Published private(set) var activeProviderID: UUID?

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "CustomAIProviderManager")
    private let providersKey = "customAIProviders"
    private let activeProviderKey = "activeCustomAIProviderID"
    private let defaults = UserDefaults.standard

    private init() {
        loadProviders()
        migrateLegacyCustomProviderIfNeeded()
        loadActiveProvider()
        activateStoredProviderIfNeeded()
    }

    var activeProvider: CustomAIProviderConfig? {
        guard let activeProviderID else { return nil }
        return providers.first { $0.id == activeProviderID }
    }

    func addProvider(_ provider: CustomAIProviderConfig, apiKey: String) -> Bool {
        providers.append(provider)
        guard APIKeyManager.shared.saveCustomAIProviderAPIKey(apiKey, forProviderId: provider.id) else {
            providers.removeAll { $0.id == provider.id }
            return false
        }
        saveProviders()

        if activeProviderID == nil {
            activateProvider(provider.id)
        }

        return true
    }

    func updateProvider(_ provider: CustomAIProviderConfig, apiKey: String?) -> Bool {
        guard let index = providers.firstIndex(where: { $0.id == provider.id }) else {
            return false
        }

        if let apiKey, !apiKey.isEmpty {
            guard APIKeyManager.shared.saveCustomAIProviderAPIKey(apiKey, forProviderId: provider.id) else {
                return false
            }
        }

        providers[index] = provider
        saveProviders()

        if activeProviderID == provider.id {
            applyLegacyCustomProvider(provider)
        }

        return true
    }

    func deleteProvider(_ provider: CustomAIProviderConfig) {
        providers.removeAll { $0.id == provider.id }
        APIKeyManager.shared.deleteCustomAIProviderAPIKey(forProviderId: provider.id)

        if activeProviderID == provider.id {
            activeProviderID = providers.first?.id
            saveActiveProviderID()
            if let next = activeProvider {
                applyLegacyCustomProvider(next)
            } else {
                clearLegacyCustomProvider()
            }
        }

        saveProviders()
    }

    func activateProvider(_ id: UUID) {
        guard providers.contains(where: { $0.id == id }) else { return }
        activeProviderID = id
        saveActiveProviderID()

        if let provider = activeProvider {
            applyLegacyCustomProvider(provider)
        }
    }

    func apiKey(for provider: CustomAIProviderConfig) -> String {
        APIKeyManager.shared.getCustomAIProviderAPIKey(forProviderId: provider.id) ?? ""
    }

    func validateProvider(name: String, baseURL: String, models: [String], excluding id: UUID? = nil) -> [String] {
        var errors: [String] = []
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModels = models.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

        if trimmedName.isEmpty {
            errors.append("Provider name cannot be empty")
        }

        if trimmedURL.isEmpty {
            errors.append("Base URL cannot be empty")
        } else if URL(string: trimmedURL)?.host == nil {
            errors.append("Base URL must be a valid URL")
        }

        if trimmedModels.isEmpty {
            errors.append("At least one model is required")
        }

        if providers.contains(where: { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame && $0.id != id }) {
            errors.append("A provider with this name already exists")
        }

        return errors
    }

    func verifyProvider(baseURL: String, apiKey: String, model: String) async -> (isValid: Bool, errorMessage: String?) {
        guard let url = URL(string: baseURL) else {
            return (false, "Invalid base URL")
        }

        return await OpenAILLMClient.verifyAPIKey(
            baseURL: url,
            apiKey: apiKey,
            model: model
        )
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

    private func loadActiveProvider() {
        guard let rawID = defaults.string(forKey: activeProviderKey),
              let id = UUID(uuidString: rawID),
              providers.contains(where: { $0.id == id }) else {
            activeProviderID = providers.first?.id
            saveActiveProviderID()
            return
        }
        activeProviderID = id
    }

    private func saveActiveProviderID() {
        defaults.set(activeProviderID?.uuidString, forKey: activeProviderKey)
    }

    private func activateStoredProviderIfNeeded() {
        guard let provider = activeProvider else { return }
        applyLegacyCustomProvider(provider)
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

    private func applyLegacyCustomProvider(_ provider: CustomAIProviderConfig) {
        defaults.set(provider.baseURL, forKey: "customProviderBaseURL")
        defaults.set(provider.selectedModel, forKey: "customProviderModel")
        defaults.set(provider.selectedModel, forKey: "\(AIProvider.custom.rawValue)SelectedModel")

        if let key = APIKeyManager.shared.getCustomAIProviderAPIKey(forProviderId: provider.id), !key.isEmpty {
            APIKeyManager.shared.saveAPIKey(key, forProvider: AIProvider.custom.rawValue)
        }

        NotificationCenter.default.post(name: .aiProviderKeyChanged, object: nil)
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }

    private func clearLegacyCustomProvider() {
        defaults.removeObject(forKey: "customProviderBaseURL")
        defaults.removeObject(forKey: "customProviderModel")
        defaults.removeObject(forKey: "\(AIProvider.custom.rawValue)SelectedModel")
        APIKeyManager.shared.deleteAPIKey(forProvider: AIProvider.custom.rawValue)
        NotificationCenter.default.post(name: .aiProviderKeyChanged, object: nil)
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }
}
