import Combine
import Foundation
import LLMkit

enum AIProvider: String, CaseIterable {
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
    case voiceInkRefine = "VoiceInk Refine"
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
            return "https://generativelanguage.googleapis.com/v1/interactions"
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
        case .voiceInkRefine:
            return ""
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
            return "gemini-3.8-flash"
        case .anthropic:
            return "claude-sonnet-5"
        case .openAI:
            return "gpt-5.6-luna"
        case .mistral:
            return "mistral-small-latest"
        case .elevenLabs:
            return "scribe_v2"
        case .deepgram:
            return "whisper-1"
        case .soniox:
            return "stt-async-v5"
        case .speechmatics:
            return "speechmatics-enhanced"
        case .assemblyAI:
            return "universal-3-5-pro"
        case .voiceInkRefine:
            return VoiceInkRefineService.modelName
        case .ollama:
            return UserDefaults.standard.string(forKey: "ollamaSelectedModel") ?? "mistral"
        case .localCLI:
            return "local-cli"
        case .custom:
            return CustomAIProviderManager.shared.defaultModelName
        case .openRouter:
            return "openai/gpt-oss-120b"
        }
    }

    var availableModels: [String] {
        switch self {
        case .cerebras:
            return [
                "gpt-oss-120b",
                "qwen-3.8-27b",
            ]
        case .groq:
            return [
                "openai/gpt-oss-120b",
                "openai/gpt-oss-20b",
                "qwen/qwen3.8-27b",
            ]
        case .gemini:
            return [
                "gemini-3.8-flash",
                "gemini-3.7-flash",
                "gemini-3.6-flash",
                "gemini-3.5-flash-lite",
                "gemini-3.5-flash",
                "gemini-3.1-pro-preview",
                "gemini-3.1-flash-lite",
                "gemini-2.5-flash-lite",
            ]
        case .anthropic:
            return [
                "claude-sonnet-5",
                "claude-haiku-4-5",
            ]
        case .openAI:
            return [
                "gpt-5.6-luna",
                "gpt-5.6-terra",
                "gpt-5.6-sol",
                "gpt-5.5",
                "gpt-5.4",
                "gpt-5.4-mini",
                "gpt-5.4-nano",
                "gpt-4.1",
                "gpt-4.1-mini",
                "gpt-4.1-nano",
            ]
        case .mistral:
            return [
                "mistral-small-latest",
                "mistral-medium-latest",
                "mistral-large-latest",
            ]
        case .elevenLabs:
            return ["scribe_v2"]
        case .deepgram:
            return ["whisper-1"]
        case .soniox:
            return ["stt-async-v5"]
        case .speechmatics:
            return ["speechmatics-enhanced"]
        case .assemblyAI:
            return ["universal-3-5-pro"]
        case .voiceInkRefine:
            return [VoiceInkRefineService.modelName]
        case .ollama:
            return []
        case .localCLI:
            return []
        case .custom:
            return CustomAIProviderManager.shared.availableModelNames
        case .openRouter:
            return []
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .voiceInkRefine, .ollama, .localCLI:
            return false
        default:
            return true
        }
    }

    var supportsEnhancement: Bool {
        switch self {
        case .elevenLabs, .deepgram, .soniox, .speechmatics, .assemblyAI:
            return false
        default:
            return true
        }
    }
}

struct OllamaRefreshResult {
    let models: [OllamaModel]
    let errorMessage: String?
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
                if selectedProvider == .localCLI {
                    self.isAPIKeyValid = localCLIService.isConfigured
                } else if selectedProvider == .voiceInkRefine {
                    self.isAPIKeyValid = voiceInkRefineService.isAvailableInModes
                } else {
                    self.isAPIKeyValid = true
                }
                if selectedProvider == .ollama {
                    Task {
                        await refreshOllamaAvailability()
                    }
                }
            }
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
        }
    }

    @Published private var selectedModels: [AIProvider: String] = [:]
    private let userDefaults = UserDefaults.standard
    let voiceInkRefineService = VoiceInkRefineService.shared
    private lazy var ollamaService = OllamaService()
    private lazy var localCLIService = LocalCLIService()
    private var apiKeyChangeObserver: NSObjectProtocol?
    private var settingsChangeObserver: NSObjectProtocol?
    private var voiceInkRefineObserver: AnyCancellable?

    @Published private var openRouterModels: [String] = []
    @Published private var openRouterModelCatalog: [OpenRouterModel] = []
    private var isOpenRouterCatalogRefreshing = false
    @Published private(set) var isOllamaRefreshing = false

    var connectedProviders: [AIProvider] {
        AIProvider.allCases.filter { provider in
            guard provider.supportsEnhancement else {
                return false
            }

            if provider == .custom {
                return CustomAIProviderManager.shared.hasConfiguredModels
            } else if provider == .voiceInkRefine {
                return voiceInkRefineService.isAvailableInModes
            } else if provider == .ollama {
                return ollamaService.isConnected
            } else if provider == .localCLI {
                return localCLIService.isConfigured
            } else if provider.requiresAPIKey {
                return APIKeyManager.shared.hasAPIKey(forProvider: provider.rawValue)
            }
            return false
        }
    }

    var currentModel: String {
        if selectedProvider == .voiceInkRefine {
            return selectedProvider.defaultModel
        }

        if let selectedModel = selectedModels[selectedProvider],
            !selectedModel.isEmpty,
            (selectedProvider == .ollama && !selectedModel.isEmpty) || availableModels.contains(selectedModel)
        {
            return selectedModel
        }
        return selectedProvider.defaultModel
    }

    func selectedModel(for provider: AIProvider) -> String {
        if provider == .voiceInkRefine {
            return provider.defaultModel
        }

        if let selectedModel = selectedModels[provider], !selectedModel.isEmpty {
            return selectedModel
        }
        return provider.defaultModel
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
        } else if provider == .custom {
            return CustomAIProviderManager.shared.availableModelNames
        }
        return provider.availableModels
    }

    init() {
        if userDefaults.string(forKey: "selectedAIProvider") == "GROQ" {
            userDefaults.set("Groq", forKey: "selectedAIProvider")
        }

        if let savedProvider = userDefaults.string(forKey: "selectedAIProvider"),
            let provider = AIProvider(rawValue: savedProvider)
        {
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
            if selectedProvider == .localCLI {
                self.isAPIKeyValid = localCLIService.isConfigured
            } else if selectedProvider == .voiceInkRefine {
                self.isAPIKeyValid = voiceInkRefineService.isAvailableInModes
            } else {
                self.isAPIKeyValid = true
            }
        }

        loadSavedModelSelections()
        loadSavedOpenRouterModels()
        initializeAutoLearnSelectionIfNeeded()

        voiceInkRefineObserver = voiceInkRefineService.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }

                if self.selectedProvider == .voiceInkRefine {
                    let isAvailable = self.voiceInkRefineService.isAvailableInModes
                    if self.isAPIKeyValid != isAvailable {
                        self.isAPIKeyValid = isAvailable
                    }
                }

                if self.voiceInkRefineService.isAvailableInModes {
                    self.initializeAutoLearnSelectionIfNeeded()
                }

                self.objectWillChange.send()
            }
        }

        apiKeyChangeObserver = NotificationCenter.default.addObserver(
            forName: .aiProviderKeyChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.reloadSelectedProviderConfiguration()
                self.initializeAutoLearnSelectionIfNeeded()
            }
        }

        settingsChangeObserver = NotificationCenter.default.addObserver(
            forName: .AppSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.initializeAutoLearnSelectionIfNeeded()
        }
    }

    deinit {
        if let apiKeyChangeObserver {
            NotificationCenter.default.removeObserver(apiKeyChangeObserver)
        }
        if let settingsChangeObserver {
            NotificationCenter.default.removeObserver(settingsChangeObserver)
        }
        voiceInkRefineObserver?.cancel()
    }

    private func reloadSelectedProviderConfiguration() {
        if selectedProvider == .custom {
            customBaseURL = userDefaults.string(forKey: "customProviderBaseURL") ?? ""
            customModel = userDefaults.string(forKey: "customProviderModel") ?? ""
        }

        let selectedModelKey = "\(selectedProvider.rawValue)SelectedModel"
        if selectedProvider == .voiceInkRefine {
            selectedModels[selectedProvider] = selectedProvider.defaultModel
        } else if let savedModel = userDefaults.string(forKey: selectedModelKey), !savedModel.isEmpty {
            selectedModels[selectedProvider] = savedModel
        }

        if selectedProvider.requiresAPIKey {
            if let savedKey = APIKeyManager.shared.getAPIKey(forProvider: selectedProvider.rawValue) {
                apiKey = savedKey
                isAPIKeyValid = true
            } else {
                apiKey = ""
                isAPIKeyValid = false
            }
        } else {
            apiKey = ""
            if selectedProvider == .localCLI {
                isAPIKeyValid = localCLIService.isConfigured
            } else if selectedProvider == .voiceInkRefine {
                isAPIKeyValid = voiceInkRefineService.isAvailableInModes
            } else {
                isAPIKeyValid = true
            }
        }
    }

    private func initializeAutoLearnSelectionIfNeeded() {
        guard AutoLearnSettings.selectedProvider == nil else { return }

        let availableProviders = connectedProviders
        let provider = availableProviders.contains(selectedProvider)
            ? selectedProvider
            : availableProviders.first
        guard let provider else { return }

        AutoLearnSettings.initializeSelectionIfNeeded(
            provider: provider,
            model: initialAutoLearnModel(for: provider)
        )
    }

    private func initialAutoLearnModel(for provider: AIProvider) -> String {
        if provider == .localCLI { return "" }
        if provider == .voiceInkRefine { return provider.defaultModel }

        let selectedModel = selectedModel(for: provider)
        let availableModels = availableModels(for: provider)
        return availableModels.contains(selectedModel)
            ? selectedModel
            : availableModels.first ?? selectedModel
    }

    private func loadSavedModelSelections() {
        for provider in AIProvider.allCases {
            if provider == .voiceInkRefine {
                selectedModels[provider] = provider.defaultModel
                continue
            }

            let key = "\(provider.rawValue)SelectedModel"
            if let savedModel = userDefaults.string(forKey: key), !savedModel.isEmpty {
                selectedModels[provider] = savedModel
            }
        }
    }

    private func loadSavedOpenRouterModels() {
        if let savedCatalog = userDefaults.data(forKey: "openRouterModelCatalog"),
            let decodedCatalog = try? JSONDecoder().decode([OpenRouterModel].self, from: savedCatalog)
        {
            openRouterModelCatalog = decodedCatalog
            openRouterModels = decodedCatalog.map(\.id)
            return
        }

        if let savedModels = userDefaults.array(forKey: "openRouterModels") as? [String] {
            openRouterModels = savedModels
        }
    }

    private func saveOpenRouterModels() {
        userDefaults.set(openRouterModels, forKey: "openRouterModels")
        if let encodedCatalog = try? JSONEncoder().encode(openRouterModelCatalog) {
            userDefaults.set(encodedCatalog, forKey: "openRouterModelCatalog")
        }
    }

    func selectModel(_ model: String) {
        selectModel(model, for: selectedProvider)
    }

    func selectModel(_ model: String, for provider: AIProvider) {
        guard !model.isEmpty else { return }

        if provider == .custom {
            guard CustomAIProviderManager.shared.applyConfiguration(forModel: model) else { return }
        }

        let resolvedModel = provider == .voiceInkRefine ? provider.defaultModel : model
        selectedModels[provider] = resolvedModel
        let key = "\(provider.rawValue)SelectedModel"
        userDefaults.set(resolvedModel, forKey: key)

        if provider == .ollama {
            updateSelectedOllamaModel(model)
        } else if provider == .custom {
            reloadSelectedProviderConfiguration()
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
            let result = await verifyAPIKey(
                key,
                for: selectedProvider,
                model: currentModel
            )
            DispatchQueue.main.async {
                completion(result.isValid, result.errorMessage)
            }
        }
    }

    func verifyAPIKey(_ key: String, for provider: AIProvider, model: String? = nil) async -> (
        isValid: Bool, errorMessage: String?
    ) {
        guard provider.requiresAPIKey else {
            return (true, nil)
        }

        let verificationModel = model ?? selectedModel(for: provider)
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
            result = await OpenRouterClient.verifyAPIKey(key)
        case .openAI:
            result = await OpenAILLMClient.verifyAPIKey(key)
        case .gemini:
            result = await GeminiLLMClient.verifyAPIKey(key)
        default:
            guard let baseURL = URL(string: provider.baseURL) else {
                return (false, "Invalid or missing base URL configuration")
            }
            result = await OpenAILLMClient.verifyAPIKey(
                baseURL: baseURL,
                apiKey: key,
                model: verificationModel
            )
        }

        return result
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
            _ = await self.refreshOllamaAvailability()
            await MainActor.run {
                completion(self.ollamaService.isConnected)
            }
        }
    }

    func fetchOllamaModels() async -> [OllamaModel] {
        let result = await refreshOllamaAvailability()
        return result.models
    }

    func refreshOllamaAvailabilityInBackground() {
        Task { [weak self] in
            guard let self else { return }
            _ = await self.refreshOllamaAvailability()
        }
    }

    @MainActor
    @discardableResult
    func refreshOllamaConnectionAndModels() async -> [OllamaModel] {
        let result = await refreshOllamaAvailability()
        return result.models
    }

    @MainActor
    func refreshOllamaAvailability() async -> OllamaRefreshResult {
        guard !isOllamaRefreshing else {
            return OllamaRefreshResult(models: ollamaService.availableModels, errorMessage: nil)
        }

        isOllamaRefreshing = true
        defer {
            isOllamaRefreshing = false
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
        }

        let result = await ollamaService.refreshConnectionAndModels()
        switch result {
        case .success(let models):
            return OllamaRefreshResult(models: models, errorMessage: nil)
        case .failure(let error):
            return OllamaRefreshResult(models: [], errorMessage: ollamaErrorMessage(for: error))
        }
    }

    private func ollamaErrorMessage(for error: Error) -> String {
        if let llmKitError = error as? LLMKitError {
            return ollamaErrorMessage(for: llmKitError)
        }

        if let localAIError = error as? LocalAIError,
            let errorDescription = localAIError.errorDescription
        {
            return errorDescription
        }

        let nsError = error as NSError
        var details = [nsError.localizedDescription]

        if let failingURL = nsError.userInfo["NSErrorFailingURLKey"] as? URL {
            details.append("URL: \(failingURL.absoluteString)")
        } else if let failingURLString = nsError.userInfo["NSErrorFailingURLStringKey"] as? String {
            details.append("URL: \(failingURLString)")
        }

        details.append("Code: \(nsError.domain) \(nsError.code)")

        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            details.append("Underlying: \(underlyingError.localizedDescription)")
            details.append("Underlying code: \(underlyingError.domain) \(underlyingError.code)")
        }

        if let streamErrorCode = nsError.userInfo["_kCFStreamErrorCodeKey"] {
            details.append("Network code: \(streamErrorCode)")
        }

        return details.joined(separator: "\n")
    }

    private func ollamaErrorMessage(for error: LLMKitError) -> String {
        switch error {
        case .httpError(let statusCode, let message):
            let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedMessage.isEmpty else { return "HTTP \(statusCode)" }
            return "HTTP \(statusCode): \(trimmedMessage)"
        default:
            return error.localizedDescription
        }
    }

    func enhanceWithOllama(text: String, systemPrompt: String, model: String? = nil, timeout: TimeInterval = 30)
        async throws -> String
    {
        try await ollamaService.enhance(text, withSystemPrompt: systemPrompt, model: model, timeout: timeout)
    }

    func enhanceWithVoiceInkRefine(transcript: String) async throws -> String {
        try await voiceInkRefineService.enhance(transcript: transcript)
    }

    func generateWithVoiceInkRefine(transcript: String, systemPrompt: String) async throws -> String {
        try await voiceInkRefineService.generate(transcript: transcript, systemPrompt: systemPrompt)
    }

    func reviewAutoLearnCandidates(
        payload: String,
        systemPrompt: String,
        provider: AIProvider,
        modelName: String?
    ) async throws -> String {
        if provider == .voiceInkRefine {
            return try await generateWithVoiceInkRefine(
                transcript: payload,
                systemPrompt: systemPrompt
            )
        }

        return try await performChatCompletion(
            provider: provider,
            modelName: modelName,
            messages: [.user(payload)],
            systemPrompt: systemPrompt,
            localUserPrompt: payload,
            temperature: 0,
            timeout: EnhancementRequestSettings.timeout
        ).text
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

    func openRouterModelMetadata(for modelName: String) -> OpenRouterModel? {
        openRouterModelCatalog.first(where: { $0.id == modelName })
    }

    @MainActor
    func fetchOpenRouterModelsIfNeededForMigration() async {
        guard openRouterModelCatalog.isEmpty,
            APIKeyManager.shared.hasAPIKey(forProvider: AIProvider.openRouter.rawValue)
        else {
            return
        }

        await fetchOpenRouterModels()
    }

    @MainActor
    func fetchOpenRouterModels() async {
        guard !isOpenRouterCatalogRefreshing else { return }
        isOpenRouterCatalogRefreshing = true
        defer { isOpenRouterCatalogRefreshing = false }

        do {
            let catalog = try await OpenRouterClient.fetchModelCatalog()
            openRouterModelCatalog = catalog
            openRouterModels = catalog.map(\.id)
            saveOpenRouterModels()
            if !openRouterModels.isEmpty,
                let savedModel = selectedModels[.openRouter],
                !openRouterModels.contains(savedModel)
            {
                let replacement = openRouterModels.contains(AIProvider.openRouter.defaultModel)
                    ? AIProvider.openRouter.defaultModel
                    : openRouterModels[0]
                selectModel(replacement, for: .openRouter)
            } else if selectedProvider == .openRouter,
                selectedModels[.openRouter] == nil,
                !openRouterModels.isEmpty
            {
                let initialModel = openRouterModels.contains(AIProvider.openRouter.defaultModel)
                    ? AIProvider.openRouter.defaultModel
                    : openRouterModels[0]
                selectModel(initialModel)
            }
            objectWillChange.send()
        } catch {
            // Keep the last successful catalog during transient OpenRouter failures.
        }
    }
}
