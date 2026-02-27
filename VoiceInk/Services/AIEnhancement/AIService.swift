import Foundation
import LLMkit

enum AIProvider: String, CaseIterable, Codable {
    case cerebras = "Cerebras"
    case groq = "Groq"
    case gemini = "Gemini"
    case anthropic = "Anthropic"
    case openAI = "OpenAI"
    case openRouter = "OpenRouter"
    case mistral = "Mistral"
    case elevenLabs = "ElevenLabs"
    case deepgram = "Deepgram"
    case soniox = "Soniox"
    case ollama = "Ollama"
    case custom = "Custom"
    
    
    var baseURL: String {
        switch self {
        case .cerebras:
            return "https://api.cerebras.ai/v1/chat/completions"
        case .groq:
            return "https://api.groq.com/openai/v1/chat/completions"
        case .gemini:
            return "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        case .anthropic:
            return "https://api.anthropic.com/v1/messages"
        case .openAI:
            return "https://api.openai.com/v1/chat/completions"
        case .openRouter:
            return "https://openrouter.ai/api/v1/chat/completions"
        case .mistral:
            return "https://api.mistral.ai/v1/chat/completions"
        case .elevenLabs:
            return "https://api.elevenlabs.io/v1/speech-to-text"
        case .deepgram:
            return "https://api.deepgram.com/v1/listen"
        case .soniox:
            return "https://api.soniox.com/v1"
        case .ollama:
            return UserDefaults.standard.string(forKey: "ollamaBaseURL") ?? "http://localhost:11434"
        case .custom:
            return UserDefaults.standard.string(forKey: "customProviderBaseURL") ?? ""
        }
    }
    
    var defaultModel: String {
        switch self {
        case .cerebras:
            return "gpt-oss-120b"
        case .groq:
            return "openai/gpt-oss-120b"
        case .gemini:
            return "gemini-2.5-flash-lite"
        case .anthropic:
            return "claude-sonnet-4-6"
        case .openAI:
            return "gpt-5.2"
        case .mistral:
            return "mistral-large-latest"
        case .elevenLabs:
            return "scribe_v1"
        case .deepgram:
            return "whisper-1"
        case .soniox:
            return "stt-async-v4"
        case .ollama:
            return UserDefaults.standard.string(forKey: "ollamaSelectedModel") ?? "mistral"
        case .custom:
            return UserDefaults.standard.string(forKey: "customProviderModel") ?? ""
        case .openRouter:
            return "openai/gpt-oss-120b"
        }
    }
    
    var availableModels: [String] {
        switch self {
        case .cerebras:
            return [
                "gpt-oss-120b",
                "llama3.1-8b",
                "qwen-3-235b-a22b-instruct-2507",
                "zai-glm-4.7"
            ]
        case .groq:
            return [
                "llama-3.1-8b-instant",
                "llama-3.3-70b-versatile",
                "moonshotai/kimi-k2-instruct-0905",
                "qwen/qwen3-32b",
                "meta-llama/llama-4-maverick-17b-128e-instruct",
                "openai/gpt-oss-120b",
                "openai/gpt-oss-20b"
            ]
        case .gemini:
            return [
                "gemini-3-flash-preview",
                "gemini-3-pro-preview",
                "gemini-2.5-pro",
                "gemini-2.5-flash",
                "gemini-2.5-flash-lite",
                "gemini-2.0-flash-001"
            ]
        case .anthropic:
            return [
                "claude-opus-4-6",
                "claude-sonnet-4-6",
                "claude-opus-4-5",
                "claude-sonnet-4-5",
                "claude-haiku-4-5"
            ]
        case .openAI:
            return [
                "gpt-5.2",
                "gpt-5.1",
                "gpt-5-mini",
                "gpt-5-nano",
                "gpt-4.1",
                "gpt-4.1-mini"
            ]
        case .mistral:
            return [
                "mistral-large-latest",
                "mistral-medium-latest",
                "mistral-small-latest",
                "mistral-saba-latest"
            ]
        case .elevenLabs:
            return ["scribe_v1", "scribe_v1_experimental"]
        case .deepgram:
            return ["whisper-1"]
        case .soniox:
            return ["stt-async-v4"]
        case .ollama:
            return []
        case .custom:
            return []
        case .openRouter:
            return []
        }
    }
    
    var requiresAPIKey: Bool {
        switch self {
        case .ollama:
            return false
        default:
            return true
        }
    }
}

class AIService: ObservableObject {
    @Published var apiKey: String = ""
    @Published var isAPIKeyValid: Bool = false
    @Published var customBaseURL: String = UserDefaults.standard.string(forKey: "customProviderBaseURL") ?? "" {
        didSet {
            userDefaults.set(customBaseURL, forKey: "customProviderBaseURL")
        }
    }
    @Published var customModel: String = UserDefaults.standard.string(forKey: "customProviderModel") ?? "" {
        didSet {
            userDefaults.set(customModel, forKey: "customProviderModel")
        }
    }
    @Published var selectedProvider: AIProvider {
        didSet {
            userDefaults.set(selectedProvider.rawValue, forKey: "selectedAIProvider")
            if selectedProvider.requiresAPIKey {
                if let savedKey = APIKeyManager.shared.getAPIKey(forProvider: selectedProvider.rawValue) {
                    self.apiKey = savedKey
                    self.isAPIKeyValid = true
                } else {
                    self.apiKey = ""
                    self.isAPIKeyValid = false
                }
            } else {
                self.apiKey = ""
                self.isAPIKeyValid = true
                if selectedProvider == .ollama {
                    Task {
                        await ollamaService.checkConnection()
                        await ollamaService.refreshModels()
                    }
                }
            }
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
        }
    }
    
    @Published private var selectedModels: [AIProvider: String] = [:]
    private let userDefaults = UserDefaults.standard
    private lazy var ollamaService = OllamaService()
    
    @Published private var openRouterModels: [String] = []
    
    @Published var providerConfigurations: [AIProviderConfiguration] = []
    private let providerConfigurationsKey = "aiProviderConfigurations"
    
    var connectedProviders: [AIProvider] {
        AIProvider.allCases.filter { provider in
            if provider == .ollama {
                return ollamaService.isConnected
            } else if provider.requiresAPIKey {
                return APIKeyManager.shared.hasAPIKey(forProvider: provider.rawValue)
            }
            return false
        }
    }
    
    var currentModel: String {
        if let selectedModel = selectedModels[selectedProvider],
           !selectedModel.isEmpty,
           (selectedProvider == .ollama && !selectedModel.isEmpty) || availableModels.contains(selectedModel) {
            return selectedModel
        }
        return selectedProvider.defaultModel
    }
    
    var availableModels: [String] {
        if selectedProvider == .ollama {
            return ollamaService.availableModels.map { $0.name }
        } else if selectedProvider == .openRouter {
            return openRouterModels
        }
        return selectedProvider.availableModels
    }
    
    init() {
        if userDefaults.string(forKey: "selectedAIProvider") == "GROQ" {
            userDefaults.set("Groq", forKey: "selectedAIProvider")
        }

        if let savedProvider = userDefaults.string(forKey: "selectedAIProvider"),
           let provider = AIProvider(rawValue: savedProvider) {
            self.selectedProvider = provider
        } else {
            self.selectedProvider = .gemini
        }

        if selectedProvider.requiresAPIKey {
            if let savedKey = APIKeyManager.shared.getAPIKey(forProvider: selectedProvider.rawValue) {
                self.apiKey = savedKey
                self.isAPIKeyValid = true
            }
        } else {
            self.isAPIKeyValid = true
        }

        loadSavedModelSelections()
        loadSavedOpenRouterModels()
        loadProviderConfigurations()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAPIKeyChanged),
            name: .aiProviderKeyChanged,
            object: nil
        )
    }

    /// Incremented when API keys change, used to force SwiftUI re-renders
    /// of views that depend on `hasAPIKey` (a computed Keychain lookup).
    @Published private(set) var apiKeyRevision: Int = 0

    @objc private func handleAPIKeyChanged() {
        DispatchQueue.main.async {
            self.apiKeyRevision += 1
        }
    }
    
    private func loadSavedModelSelections() {
        for provider in AIProvider.allCases {
            let key = "\(provider.rawValue)SelectedModel"
            if let savedModel = userDefaults.string(forKey: key), !savedModel.isEmpty {
                selectedModels[provider] = savedModel
            }
        }
    }
    
    private func loadSavedOpenRouterModels() {
        if let savedModels = userDefaults.array(forKey: "openRouterModels") as? [String] {
            openRouterModels = savedModels
        }
    }
    
    private func saveOpenRouterModels() {
        userDefaults.set(openRouterModels, forKey: "openRouterModels")
    }
    
    func selectModel(_ model: String) {
        guard !model.isEmpty else { return }
        
        selectedModels[selectedProvider] = model
        let key = "\(selectedProvider.rawValue)SelectedModel"
        userDefaults.set(model, forKey: key)
        
        if selectedProvider == .ollama {
            updateSelectedOllamaModel(model)
        }
        
        objectWillChange.send()
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }
    
    func saveAPIKey(_ key: String, completion: @escaping (Bool, String?) -> Void) {
        guard selectedProvider.requiresAPIKey else {
            completion(true, nil)
            return
        }

        verifyAPIKey(key) { [weak self] isValid, errorMessage in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if isValid {
                    self.apiKey = key
                    self.isAPIKeyValid = true
                    APIKeyManager.shared.saveAPIKey(key, forProvider: self.selectedProvider.rawValue)
                    NotificationCenter.default.post(name: .aiProviderKeyChanged, object: nil)
                } else {
                    self.isAPIKeyValid = false
                }
                completion(isValid, errorMessage)
            }
        }
    }
    
    func verifyAPIKey(_ key: String, completion: @escaping (Bool, String?) -> Void) {
        guard selectedProvider.requiresAPIKey else {
            completion(true, nil)
            return
        }

        Task {
            let result: (isValid: Bool, errorMessage: String?)
            switch selectedProvider {
            case .anthropic:
                result = await AnthropicLLMClient.verifyAPIKey(key)
            case .elevenLabs:
                result = await ElevenLabsClient.verifyAPIKey(key)
            case .deepgram:
                result = await DeepgramClient.verifyAPIKey(key)
            case .mistral:
                result = await MistralTranscriptionClient.verifyAPIKey(key)
            case .soniox:
                result = await SonioxClient.verifyAPIKey(key)
            case .openRouter:
                result = await OpenRouterClient.verifyAPIKey(key, model: currentModel)
            case .gemini:
                result = await GeminiTranscriptionClient.verifyAPIKey(key)
            default:
                guard let baseURL = URL(string: selectedProvider.baseURL) else {
                    DispatchQueue.main.async {
                        completion(false, "Invalid or missing base URL configuration")
                    }
                    return
                }
                result = await OpenAILLMClient.verifyAPIKey(
                    baseURL: baseURL,
                    apiKey: key,
                    model: currentModel
                )
            }
            DispatchQueue.main.async {
                completion(result.isValid, result.errorMessage)
            }
        }
    }
    
    func clearAPIKey() {
        guard selectedProvider.requiresAPIKey else { return }

        apiKey = ""
        isAPIKeyValid = false
        APIKeyManager.shared.deleteAPIKey(forProvider: selectedProvider.rawValue)
        NotificationCenter.default.post(name: .aiProviderKeyChanged, object: nil)
    }
    
    func checkOllamaConnection(completion: @escaping (Bool) -> Void) {
        Task { [weak self] in
            guard let self = self else { return }
            await self.ollamaService.checkConnection()
            DispatchQueue.main.async {
                completion(self.ollamaService.isConnected)
            }
        }
    }
    
    func fetchOllamaModels() async -> [OllamaModel] {
        await ollamaService.refreshModels()
        return ollamaService.availableModels
    }
    
    func enhanceWithOllama(text: String, systemPrompt: String, baseURL: String? = nil, model: String? = nil) async throws -> String {
        let savedBaseURL = ollamaService.baseURL
        let savedModel = ollamaService.selectedModel
        
        if let baseURL = baseURL {
            ollamaService.baseURL = baseURL
        }
        if let model = model {
            ollamaService.selectedModel = model
        }
        
        do {
            let result = try await ollamaService.enhance(text, withSystemPrompt: systemPrompt)
            ollamaService.baseURL = savedBaseURL
            ollamaService.selectedModel = savedModel
            return result
        } catch {
            ollamaService.baseURL = savedBaseURL
            ollamaService.selectedModel = savedModel
            throw error
        }
    }
    
    func updateOllamaBaseURL(_ newURL: String) {
        ollamaService.baseURL = newURL
        userDefaults.set(newURL, forKey: "ollamaBaseURL")
    }
    
    func updateSelectedOllamaModel(_ modelName: String) {
        ollamaService.selectedModel = modelName
        userDefaults.set(modelName, forKey: "ollamaSelectedModel")
    }
    
    func fetchOpenRouterModels() async {
        do {
            let models = try await OpenRouterClient.fetchModels()
            await MainActor.run {
                self.openRouterModels = models
                self.saveOpenRouterModels()
                if self.selectedProvider == .openRouter && self.currentModel == self.selectedProvider.defaultModel && !models.isEmpty {
                    self.selectModel(models.first!)
                }
                self.objectWillChange.send()
            }
        } catch {
            await MainActor.run {
                self.openRouterModels = []
                self.saveOpenRouterModels()
                self.objectWillChange.send()
            }
        }
    }

    
    // MARK: - Provider Configurations

    /// Callback to clear `providerConfigurationId` on prompts that reference a deleted config.
    /// Set by `AIEnhancementService` after initialization.
    var onProviderConfigDeleted: ((_ deletedConfigId: UUID) -> Void)?

    var defaultProviderConfiguration: AIProviderConfiguration? {
        providerConfigurations.first(where: { $0.isDefault })
    }

    private func loadProviderConfigurations() {
        if let data = userDefaults.data(forKey: providerConfigurationsKey) {
            do {
                providerConfigurations = try JSONDecoder().decode([AIProviderConfiguration].self, from: data)
            } catch {
                providerConfigurations = []
            }
        }

        migrateExistingProviderIfNeeded()
        ensureDefaultExists()
    }

    /// Ensures exactly one configuration is marked as default.
    /// Repairs corrupted state (zero or multiple defaults).
    private func ensureDefaultExists() {
        guard !providerConfigurations.isEmpty else { return }

        let defaults = providerConfigurations.filter { $0.isDefault }
        if defaults.count == 1 { return }

        // Clear all defaults, then set the first one
        for i in providerConfigurations.indices {
            providerConfigurations[i].isDefault = false
        }
        providerConfigurations[0].isDefault = true
        saveProviderConfigurations()
    }

    private func migrateExistingProviderIfNeeded() {
        // Only migrate when user has no configurations yet.
        // This runs on every launch until the user has at least one config
        // (either from migration or manually added), avoiding the problem
        // where a one-shot migration flag gets burned on a failed attempt.
        guard providerConfigurations.isEmpty else { return }

        let enhancementProviders: [AIProvider] = AIProvider.allCases.filter {
            $0 != .elevenLabs && $0 != .deepgram && $0 != .soniox
        }

        for provider in enhancementProviders {
            if provider == .ollama {
                // Create an Ollama config only if it was the selected provider
                guard provider == selectedProvider else { continue }
            } else {
                guard provider.requiresAPIKey else { continue }
                guard APIKeyManager.shared.hasAPIKey(forProvider: provider.rawValue) else { continue }
            }

            let modelKey = "\(provider.rawValue)SelectedModel"
            let model = userDefaults.string(forKey: modelKey) ?? provider.defaultModel

            var baseURL: String? = nil
            var customModelValue: String? = nil
            if provider == .ollama {
                let savedURL = userDefaults.string(forKey: "ollamaBaseURL") ?? ""
                if !savedURL.isEmpty { baseURL = savedURL }
            } else if provider == .custom {
                let savedBaseURL = userDefaults.string(forKey: "customProviderBaseURL") ?? ""
                if !savedBaseURL.isEmpty { baseURL = savedBaseURL }
                let savedModel = userDefaults.string(forKey: "customProviderModel") ?? ""
                if !savedModel.isEmpty { customModelValue = savedModel }
            }

            // Mark the previously selected global provider as default
            let isCurrentGlobal = (provider == selectedProvider)

            let config = AIProviderConfiguration(
                name: provider.rawValue,
                provider: provider,
                model: model,
                customBaseURL: baseURL,
                customModel: customModelValue,
                isDefault: isCurrentGlobal
            )
            providerConfigurations.append(config)
        }

        if !providerConfigurations.isEmpty {
            saveProviderConfigurations()
        }
    }

    private func saveProviderConfigurations() {
        do {
            let data = try JSONEncoder().encode(providerConfigurations)
            userDefaults.set(data, forKey: providerConfigurationsKey)
        } catch {
            // Encoding failed silently
        }
    }

    func addProviderConfiguration(_ config: AIProviderConfiguration) {
        var newConfig = config
        // First config added automatically becomes the default
        if providerConfigurations.isEmpty {
            newConfig.isDefault = true
        }
        providerConfigurations.append(newConfig)
        saveProviderConfigurations()
    }

    func updateProviderConfiguration(_ config: AIProviderConfiguration) {
        guard let index = providerConfigurations.firstIndex(where: { $0.id == config.id }) else { return }
        var updated = config
        // Preserve isDefault — callers must use setDefaultProviderConfiguration() to change it
        updated.isDefault = providerConfigurations[index].isDefault
        providerConfigurations[index] = updated
        saveProviderConfigurations()
    }

    /// Deletes a provider configuration. The default configuration cannot be deleted.
    /// Any prompts referencing the deleted config have their assignment cleared (falling back to default).
    /// - Returns: `true` if the config was deleted, `false` if it was the default (protected).
    @discardableResult
    func deleteProviderConfiguration(_ config: AIProviderConfiguration) -> Bool {
        guard !config.isDefault else { return false }
        providerConfigurations.removeAll { $0.id == config.id }
        saveProviderConfigurations()
        onProviderConfigDeleted?(config.id)
        return true
    }

    func setDefaultProviderConfiguration(_ config: AIProviderConfiguration) {
        for i in providerConfigurations.indices {
            providerConfigurations[i].isDefault = (providerConfigurations[i].id == config.id)
        }
        saveProviderConfigurations()
    }

    func resolveProviderConfig(forId configId: UUID?) -> ResolvedProviderConfig {
        // Look up by explicit ID
        if let configId = configId,
           let config = providerConfigurations.first(where: { $0.id == configId }) {
            return resolvedConfig(from: config)
        }

        // Fall back to the default configuration
        if let defaultConfig = defaultProviderConfiguration {
            return resolvedConfig(from: defaultConfig)
        }

        // Last resort: global provider settings (no configs exist yet)
        return ResolvedProviderConfig(
            provider: selectedProvider,
            apiKey: apiKey,
            model: currentModel,
            baseURL: selectedProvider == .custom ? customBaseURL : selectedProvider.baseURL
        )
    }

    private func resolvedConfig(from config: AIProviderConfiguration) -> ResolvedProviderConfig {
        let key: String
        if config.provider.requiresAPIKey {
            key = APIKeyManager.shared.getAPIKey(forProvider: config.provider.rawValue) ?? ""
        } else {
            key = ""
        }
        return ResolvedProviderConfig(
            provider: config.provider,
            apiKey: key,
            model: config.effectiveModel,
            baseURL: config.effectiveBaseURL
        )
    }
    
    func saveAPIKeyForProvider(_ key: String, provider: AIProvider, model: String = "", completion: @escaping (Bool, String?) -> Void) {
        guard provider.requiresAPIKey else {
            completion(true, nil)
            return
        }

        let effectiveModel = model.isEmpty ? provider.defaultModel : model

        Task {
            let result: (isValid: Bool, errorMessage: String?)
            switch provider {
            case .anthropic:
                result = await AnthropicLLMClient.verifyAPIKey(key)
            case .elevenLabs:
                result = await ElevenLabsClient.verifyAPIKey(key)
            case .deepgram:
                result = await DeepgramClient.verifyAPIKey(key)
            case .mistral:
                result = await MistralTranscriptionClient.verifyAPIKey(key)
            case .soniox:
                result = await SonioxClient.verifyAPIKey(key)
            case .openRouter:
                result = await OpenRouterClient.verifyAPIKey(key, model: effectiveModel)
            case .gemini:
                result = await GeminiTranscriptionClient.verifyAPIKey(key)
            default:
                guard let baseURL = URL(string: provider.baseURL) else {
                    DispatchQueue.main.async {
                        completion(false, "Invalid or missing base URL configuration")
                    }
                    return
                }
                result = await OpenAILLMClient.verifyAPIKey(
                    baseURL: baseURL,
                    apiKey: key,
                    model: effectiveModel
                )
            }
            DispatchQueue.main.async {
                if result.isValid {
                    APIKeyManager.shared.saveAPIKey(key, forProvider: provider.rawValue)
                    NotificationCenter.default.post(name: .aiProviderKeyChanged, object: nil)
                    // If this is also the current global provider, update its state
                    if provider == self.selectedProvider {
                        self.apiKey = key
                        self.isAPIKeyValid = true
                    }
                }
                completion(result.isValid, result.errorMessage)
            }
        }
    }
}


