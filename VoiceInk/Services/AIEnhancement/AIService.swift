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
    case speechmatics = "Speechmatics"
    case assemblyAI = "AssemblyAI"
    case ollama = "Ollama"
    case localCLI = "Local CLI"
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
        case .speechmatics:
            return "https://asr.api.speechmatics.com/v2"
        case .assemblyAI:
            return "https://api.assemblyai.com/v2/transcript"
        case .ollama:
            return UserDefaults.standard.string(forKey: "ollamaBaseURL") ?? "http://localhost:11434"
        case .localCLI:
            return ""
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
            return "gpt-5.4"
        case .mistral:
            return "mistral-large-latest"
        case .elevenLabs:
            return "scribe_v1"
        case .deepgram:
            return "whisper-1"
        case .soniox:
            return "stt-async-v4"
        case .speechmatics:
            return "speechmatics-enhanced"
        case .assemblyAI:
            return "universal-3-pro"
        case .ollama:
            return UserDefaults.standard.string(forKey: "ollamaSelectedModel") ?? "mistral"
        case .localCLI:
            return "local-cli"
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
                "zai-glm-4.7"
            ]
        case .groq:
            return [
                "llama-3.1-8b-instant",
                "llama-3.3-70b-versatile",
                "qwen/qwen3-32b",
                "openai/gpt-oss-120b",
                "openai/gpt-oss-20b"
            ]
        case .gemini:
            return [
                "gemini-3.5-flash",
                "gemini-3.1-pro-preview",
                "gemini-3-flash-preview",
                "gemini-3.1-flash-lite",
                "gemini-2.5-pro",
                "gemini-2.5-flash",
                "gemini-2.5-flash-lite"
            ]
        case .anthropic:
            return [
                "claude-opus-4-7",
                "claude-opus-4-6",
                "claude-sonnet-4-6",
                "claude-opus-4-5",
                "claude-sonnet-4-5",
                "claude-haiku-4-5"
            ]
        case .openAI:
            return [
                "gpt-5.5",
                "gpt-5.4",
                "gpt-5.4-mini",
                "gpt-5.4-nano",
                "gpt-5.2",
                "gpt-4.1",
                "gpt-4.1-mini",
                "gpt-4.1-nano"
            ]
        case .mistral:
            return [
                "mistral-large-latest",
                "mistral-medium-latest",
                "mistral-small-latest"
            ]
        case .elevenLabs:
            return ["scribe_v1", "scribe_v2"]
        case .deepgram:
            return ["whisper-1"]
        case .soniox:
            return ["stt-async-v4"]
        case .speechmatics:
            return ["speechmatics-enhanced"]
        case .assemblyAI:
            return ["universal-3-pro"]
        case .ollama:
            return []
        case .localCLI:
            return []
        case .custom:
            return []
        case .openRouter:
            return []
        }
    }
    
    var requiresAPIKey: Bool {
        switch self {
        case .ollama, .localCLI:
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
                self.isAPIKeyValid = selectedProvider == .localCLI ? localCLIService.isConfigured : true
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
    private lazy var localCLIService = LocalCLIService()
    
    @Published private(set) var openRouterModels: [String] = []
    
    @Published var providerConfigurations: [AIProviderConfiguration] = []
    private let providerConfigurationsKey = "aiProviderConfigurations"
    
    var connectedProviders: [AIProvider] {
        AIProvider.allCases.filter { provider in
            if provider == .ollama {
                return ollamaService.isConnected
            } else if provider == .localCLI {
                return localCLIService.isConfigured
            } else if provider.requiresAPIKey {
                return APIKeyManager.shared.hasAPIKey(forProvider: provider.rawValue)
            }
            return false
        }
    }
    
    var connectedLLMProviders: [AIProvider] {
        AIProvider.allCases.filter { provider in
            guard provider.isLLMProvider else { return false }
            if provider == .ollama {
                return ollamaService.isConnected
            } else if provider == .localCLI {
                return localCLIService.isConfigured
            } else if provider.requiresAPIKey {
                return APIKeyManager.shared.hasAPIKey(forProvider: provider.rawValue)
            }
            return false
        }
    }
    
    func getModel(for provider: AIProvider) -> String {
        if let savedModel = userDefaults.string(forKey: "\(provider.rawValue)SelectedModel"), !savedModel.isEmpty {
            return savedModel
        }
        return provider.defaultModel
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
        availableModels(for: selectedProvider)
    }

    var localCLICommandTemplate: String {
        localCLIService.commandTemplate
    }

    var localCLITemplateSelection: LocalCLITemplate {
        localCLIService.selectedTemplate
    }

    var localCLITimeoutSeconds: Double {
        localCLIService.timeoutSeconds
    }

    func availableModels(for provider: AIProvider) -> [String] {
        if provider == .ollama {
            return ollamaService.availableModels.map { $0.name }
        } else if provider == .openRouter {
            return openRouterModels
        }
        return provider.availableModels
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
            self.isAPIKeyValid = selectedProvider == .localCLI ? localCLIService.isConfigured : true
        }

        loadSavedModelSelections()
        loadSavedOpenRouterModels()
        loadProviderConfigurations()
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
            case .speechmatics:
                result = await SpeechmaticsClient.verifyAPIKey(key)
            case .assemblyAI:
                result = await AssemblyAIClient.verifyAPIKey(key)
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
    
    func enhanceWithOllama(text: String, systemPrompt: String, timeout: TimeInterval = 30) async throws -> String {
        try await ollamaService.enhance(text, withSystemPrompt: systemPrompt, timeout: timeout)
    }
    
    func updateOllamaBaseURL(_ newURL: String) {
        ollamaService.baseURL = newURL
        userDefaults.set(newURL, forKey: "ollamaBaseURL")
    }
    
    func updateSelectedOllamaModel(_ modelName: String) {
        ollamaService.selectedModel = modelName
        userDefaults.set(modelName, forKey: "ollamaSelectedModel")
    }

    func loadLocalCLITemplate(_ template: LocalCLITemplate) {
        localCLIService.loadTemplate(template)
        refreshLocalCLIConfigurationState()
    }

    func updateLocalCLICommandTemplate(_ command: String) {
        localCLIService.commandTemplate = command
        refreshLocalCLIConfigurationState()
    }

    func updateLocalCLITimeoutSeconds(_ timeout: Double) {
        localCLIService.timeoutSeconds = timeout
        refreshLocalCLIConfigurationState()
    }

    func enhanceWithLocalCLI(systemPrompt: String, userPrompt: String) async throws -> String {
        try await localCLIService.enhance(systemPrompt: systemPrompt, userPrompt: userPrompt)
    }

    private func refreshLocalCLIConfigurationState() {
        if selectedProvider == .localCLI {
            isAPIKeyValid = localCLIService.isConfigured
        }
        objectWillChange.send()
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
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

    private func ensureDefaultExists() {
        guard !providerConfigurations.isEmpty else { return }
        let defaults = providerConfigurations.filter { $0.isDefault }
        if defaults.count == 1 { return }
        for i in providerConfigurations.indices {
            providerConfigurations[i].isDefault = false
        }
        providerConfigurations[0].isDefault = true
        saveProviderConfigurations()
    }

    private func migrateExistingProviderIfNeeded() {
        guard providerConfigurations.isEmpty else { return }

        let enhancementProviders: [AIProvider] = AIProvider.allCases.filter {
            $0 != .elevenLabs && $0 != .deepgram && $0 != .soniox && $0 != .speechmatics && $0 != .assemblyAI
        }

        for provider in enhancementProviders {
            if provider == .ollama || provider == .localCLI {
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
        if providerConfigurations.isEmpty {
            newConfig.isDefault = true
        }
        providerConfigurations.append(newConfig)
        saveProviderConfigurations()
    }

    func updateProviderConfiguration(_ config: AIProviderConfiguration) {
        guard let index = providerConfigurations.firstIndex(where: { $0.id == config.id }) else { return }
        var updated = config
        updated.isDefault = providerConfigurations[index].isDefault
        providerConfigurations[index] = updated
        saveProviderConfigurations()
    }

    @discardableResult
    func deleteProviderConfiguration(_ config: AIProviderConfiguration) -> Bool {
        guard !config.isDefault else { return false }
        providerConfigurations.removeAll { $0.id == config.id }
        saveProviderConfigurations()
        onProviderConfigDeleted?(config.id)
        return true
    }

    func setDefaultProviderConfiguration(_ config: AIProviderConfiguration) {
        guard providerConfigurations.contains(where: { $0.id == config.id }) else { return }
        for i in providerConfigurations.indices {
            providerConfigurations[i].isDefault = (providerConfigurations[i].id == config.id)
        }
        saveProviderConfigurations()
    }

    func resolveProviderConfig(forId configId: UUID?) -> ResolvedProviderConfig {
        if let configId = configId,
           let config = providerConfigurations.first(where: { $0.id == configId }) {
            return resolvedConfig(from: config)
        }
        if let defaultConfig = defaultProviderConfiguration {
            return resolvedConfig(from: defaultConfig)
        }
        // Last resort: global provider settings
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
            case .speechmatics:
                result = await SpeechmaticsClient.verifyAPIKey(key)
            case .assemblyAI:
                result = await AssemblyAIClient.verifyAPIKey(key)
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

extension AIProvider {
    var isLLMProvider: Bool {
        switch self {
        case .cerebras, .groq, .gemini, .anthropic, .openAI, .openRouter, .mistral, .ollama, .localCLI, .custom:
            return true
        default:
            return false
        }
    }
    
    var isCloudProvider: Bool {
        switch self {
        case .cerebras, .groq, .gemini, .anthropic, .openAI, .openRouter, .mistral, .custom:
            return true
        default:
            return false
        }
    }
}

