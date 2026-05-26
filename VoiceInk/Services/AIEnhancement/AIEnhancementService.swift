import Foundation
import SwiftData
import AppKit
import os
import LLMkit

enum EnhancementPrompt {
    case transcriptionEnhancement
    case aiAssistant
}

@MainActor
class AIEnhancementService: ObservableObject {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "AIEnhancementService")

    @Published var isEnhancementEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnhancementEnabled, forKey: "isAIEnhancementEnabled")
            if isEnhancementEnabled && selectedPromptId == nil {
                selectedPromptId = customPrompts.first?.id
            }
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
            NotificationCenter.default.post(name: .enhancementToggleChanged, object: nil)
        }
    }

    @Published var useClipboardContext: Bool {
        didSet {
            UserDefaults.standard.set(useClipboardContext, forKey: "useClipboardContext")
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
        }
    }

    @Published var useSelectedTextContext: Bool {
        didSet {
            UserDefaults.standard.set(useSelectedTextContext, forKey: "useSelectedTextContext")
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
        }
    }

    @Published var useScreenCaptureContext: Bool {
        didSet {
            UserDefaults.standard.set(useScreenCaptureContext, forKey: "useScreenCaptureContext")
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
        }
    }

    @Published var customPrompts: [CustomPrompt] {
        didSet {
            if let encoded = try? JSONEncoder().encode(customPrompts) {
                UserDefaults.standard.set(encoded, forKey: "customPrompts")
            }
        }
    }

    @Published var selectedPromptId: UUID? {
        didSet {
            UserDefaults.standard.set(selectedPromptId?.uuidString, forKey: "selectedPromptId")
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
            NotificationCenter.default.post(name: .promptSelectionChanged, object: nil)
        }
    }

    @Published var lastSystemMessageSent: String?
    @Published var lastUserMessageSent: String?

    var activePrompt: CustomPrompt? {
        allPrompts.first { $0.id == selectedPromptId }
    }

    var allPrompts: [CustomPrompt] {
        return customPrompts
    }

    private let aiService: AIService
    private let screenCaptureService: ScreenCaptureService
    private let customVocabularyService: CustomVocabularyService
    private var baseTimeout: TimeInterval {
        let stored = UserDefaults.standard.integer(forKey: "EnhancementTimeoutSeconds")
        return stored > 0 ? TimeInterval(stored) : 7
    }
    private let rateLimitInterval: TimeInterval = 1.0
    private var lastRequestTime: Date?
    private let modelContext: ModelContext
    
    @Published var lastCapturedClipboard: String?

    init(aiService: AIService = AIService(), modelContext: ModelContext) {
        self.aiService = aiService
        self.modelContext = modelContext
        self.screenCaptureService = ScreenCaptureService()
        self.customVocabularyService = CustomVocabularyService.shared

        self.isEnhancementEnabled = UserDefaults.standard.bool(forKey: "isAIEnhancementEnabled")
        self.useClipboardContext = UserDefaults.standard.bool(forKey: "useClipboardContext")
        if UserDefaults.standard.object(forKey: "useSelectedTextContext") == nil {
            self.useSelectedTextContext = true
        } else {
            self.useSelectedTextContext = UserDefaults.standard.bool(forKey: "useSelectedTextContext")
        }
        self.useScreenCaptureContext = UserDefaults.standard.bool(forKey: "useScreenCaptureContext")
        if let savedPromptsData = UserDefaults.standard.data(forKey: "customPrompts"),
           let decodedPrompts = try? JSONDecoder().decode([CustomPrompt].self, from: savedPromptsData) {
            self.customPrompts = decodedPrompts
        } else {
            self.customPrompts = []
        }

        if let savedPromptId = UserDefaults.standard.string(forKey: "selectedPromptId") {
            self.selectedPromptId = UUID(uuidString: savedPromptId)
        }

        if isEnhancementEnabled && (selectedPromptId == nil || !allPrompts.contains(where: { $0.id == selectedPromptId })) {
            self.selectedPromptId = allPrompts.first?.id
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAPIKeyChange),
            name: .aiProviderKeyChanged,
            object: nil
        )

        initializePredefinedPrompts()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleAPIKeyChange() {
        DispatchQueue.main.async {
            self.objectWillChange.send()
            if !self.aiService.isAPIKeyValid {
                self.isEnhancementEnabled = false
            }
        }
    }

    func getAIService() -> AIService? {
        return aiService
    }

    var isConfigured: Bool {
        aiService.isAPIKeyValid
    }

    func isConfigured(for configuration: EnhancementRuntimeConfiguration) -> Bool {
        guard let provider = configuration.provider else { return false }

        if provider == .localCLI || provider == .ollama {
            return true
        }

        if provider == .custom {
            guard let modelName = configuration.modelName else { return false }
            return CustomAIProviderManager.shared.requestConfiguration(forModel: modelName) != nil
        }

        return APIKeyManager.shared.hasAPIKey(forProvider: provider.rawValue)
    }

    private func waitForRateLimit() async throws {
        if let lastRequest = lastRequestTime {
            let timeSinceLastRequest = Date().timeIntervalSince(lastRequest)
            if timeSinceLastRequest < rateLimitInterval {
                try await Task.sleep(nanoseconds: UInt64((rateLimitInterval - timeSinceLastRequest) * 1_000_000_000))
            }
        }
        lastRequestTime = Date()
    }

    private func getSystemMessage(for mode: EnhancementPrompt, configuration: EnhancementRuntimeConfiguration? = nil) async -> String {
        let useSelectedText = configuration?.useSelectedTextContext ?? useSelectedTextContext
        let useClipboard = configuration?.useClipboardContext ?? useClipboardContext
        let useScreenCapture = configuration?.useScreenCaptureContext ?? useScreenCaptureContext

        if useClipboard {
            captureClipboardContext()
        } else {
            lastCapturedClipboard = nil
        }

        if useScreenCapture {
            screenCaptureService.lastCapturedText = nil
            await captureScreenContext()
        } else {
            screenCaptureService.lastCapturedText = nil
        }

        let selectedTextContext: String
        if useSelectedText && AXIsProcessTrusted() {
            if let selectedText = await SelectedTextService.fetchSelectedText(), !selectedText.isEmpty {
                selectedTextContext = "\n\n<CURRENTLY_SELECTED_TEXT>\n\(selectedText)\n</CURRENTLY_SELECTED_TEXT>"
            } else {
                selectedTextContext = ""
            }
        } else {
            selectedTextContext = ""
        }

        let clipboardContext = if useClipboard,
                              let clipboardText = lastCapturedClipboard,
                              !clipboardText.isEmpty {
            "\n\n<CLIPBOARD_CONTEXT>\n\(clipboardText)\n</CLIPBOARD_CONTEXT>"
        } else {
            ""
        }

        let screenCaptureContext = if useScreenCapture,
                                   let capturedText = screenCaptureService.lastCapturedText,
                                   !capturedText.isEmpty {
            "\n\n<CURRENT_WINDOW_CONTEXT>\n\(capturedText)\n</CURRENT_WINDOW_CONTEXT>"
        } else {
            ""
        }

        let customVocabulary = customVocabularyService.getCustomVocabulary(from: modelContext)

        let allContextSections = selectedTextContext + clipboardContext + screenCaptureContext

        let customVocabularySection = if !customVocabulary.isEmpty {
            """


            The following are important vocabulary words, proper nouns, and technical terms. When these words or similar-sounding words appear in the <TRANSCRIPT>, ensure they are spelled EXACTLY as shown below:
            <CUSTOM_VOCABULARY>
            \(customVocabulary)
            </CUSTOM_VOCABULARY>
            """
        } else {
            ""
        }

        let finalContextSection = allContextSections + customVocabularySection

        if let activePrompt = configuration?.prompt ?? activePrompt {
            if activePrompt.id == PredefinedPrompts.assistantPromptId {
                return activePrompt.promptText + finalContextSection
            } else {
                return activePrompt.finalPromptText + finalContextSection
            }
        } else {
            let defaultPrompt = allPrompts.first(where: { $0.id == PredefinedPrompts.defaultPromptId }) ?? allPrompts.first!
            return defaultPrompt.finalPromptText + finalContextSection
        }
    }

    private func makeRequest(text: String, mode: EnhancementPrompt, configuration: EnhancementRuntimeConfiguration? = nil) async throws -> String {
        if let configuration {
            guard isConfigured(for: configuration) else {
                throw EnhancementError.notConfigured
            }
        } else {
            guard isConfigured else {
                throw EnhancementError.notConfigured
            }
        }

        let provider: AIProvider
        let modelName: String
        if let configuration {
            guard let configuredProvider = configuration.provider else {
                throw EnhancementError.notConfigured
            }
            provider = configuredProvider
            modelName = configuration.modelName ?? configuredProvider.defaultModel
        } else {
            provider = aiService.selectedProvider
            modelName = aiService.currentModel
        }

        guard !text.isEmpty else {
            return ""
        }

        let formattedText = "\n<TRANSCRIPT>\n\(text)\n</TRANSCRIPT>"
        let systemMessage = await getSystemMessage(for: mode, configuration: configuration)

        await MainActor.run {
            self.lastSystemMessageSent = systemMessage
            self.lastUserMessageSent = formattedText
        }

        if provider == .ollama {
            do {
                let result = try await aiService.enhanceWithOllama(
                    text: formattedText,
                    systemPrompt: systemMessage,
                    model: modelName,
                    timeout: baseTimeout
                )
                return AIEnhancementOutputFilter.filter(result)
            } catch {
                if let localError = error as? LocalAIError {
                    switch localError {
                    case .timeout:
                        throw EnhancementError.timeout
                    default:
                        throw EnhancementError.customError(localError.errorDescription ?? "An unknown Ollama error occurred.")
                    }
                } else {
                    throw EnhancementError.customError(error.localizedDescription)
                }
            }
        }

        if provider == .localCLI {
            do {
                let result = try await aiService.enhanceWithLocalCLI(systemPrompt: systemMessage, userPrompt: formattedText)
                return AIEnhancementOutputFilter.filter(result)
            } catch {
                if let localError = error as? LocalCLIError {
                    throw EnhancementError.customError(localError.errorDescription ?? "An unknown Local CLI error occurred.")
                } else {
                    throw EnhancementError.customError(error.localizedDescription)
                }
            }
        }

        try await waitForRateLimit()

        do {
            let result: String
            switch provider {
            case .anthropic:
                result = try await AnthropicLLMClient.chatCompletion(
                    apiKey: try apiKey(for: provider, modelName: modelName),
                    model: modelName,
                    messages: [.user(formattedText)],
                    systemPrompt: systemMessage,
                    timeout: baseTimeout
                )
            case .custom:
                guard let customConfiguration = CustomAIProviderManager.shared.requestConfiguration(forModel: modelName),
                      let baseURL = URL(string: customConfiguration.baseURL) else {
                    throw EnhancementError.notConfigured
                }
                result = try await OpenAILLMClient.chatCompletion(
                    baseURL: baseURL,
                    apiKey: customConfiguration.apiKey,
                    model: customConfiguration.modelName,
                    messages: [.user(formattedText)],
                    systemPrompt: systemMessage,
                    temperature: 0.3,
                    timeout: baseTimeout
                )
            default:
                guard let baseURL = URL(string: provider.baseURL) else {
                    throw EnhancementError.customError("\(provider.rawValue) has an invalid API endpoint URL. Please update it in AI settings.")
                }
                let temperature = modelName.lowercased().hasPrefix("gpt-5") ? 1.0 : 0.3
                let reasoningEffort = ReasoningConfig.getReasoningParameter(
                    for: provider,
                    modelName: modelName
                )
                let extraBody = ReasoningConfig.getExtraBodyParameters(
                    for: provider,
                    modelName: modelName
                )
                result = try await OpenAILLMClient.chatCompletion(
                    baseURL: baseURL,
                    apiKey: try apiKey(for: provider, modelName: modelName),
                    model: modelName,
                    messages: [.user(formattedText)],
                    systemPrompt: systemMessage,
                    temperature: temperature,
                    reasoningEffort: reasoningEffort,
                    extraBody: extraBody,
                    timeout: baseTimeout
                )
            }
            return AIEnhancementOutputFilter.filter(result.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch let error as LLMKitError {
            throw mapLLMKitError(error)
        } catch let error as EnhancementError {
            throw error
        } catch {
            throw EnhancementError.customError(error.localizedDescription)
        }
    }

    private func apiKey(for provider: AIProvider, modelName: String) throws -> String {
        if provider == .custom {
            guard let customConfiguration = CustomAIProviderManager.shared.requestConfiguration(forModel: modelName) else {
                throw EnhancementError.notConfigured
            }
            return customConfiguration.apiKey
        }

        guard let key = APIKeyManager.shared.getAPIKey(forProvider: provider.rawValue), !key.isEmpty else {
            throw EnhancementError.notConfigured
        }
        return key
    }

    private func mapLLMKitError(_ error: LLMKitError) -> EnhancementError {
        switch error {
        case .missingAPIKey:
            return .notConfigured
        case .httpError(let statusCode, let message):
            if statusCode == 429 { return .rateLimitExceeded }
            if (500...599).contains(statusCode) { return .serverError }
            return .customError("HTTP \(statusCode): \(message)")
        case .noResultReturned:
            return .enhancementFailed
        case .networkError:
            return .networkError
        case .timeout:
            return .timeout
        case .invalidURL, .decodingError, .encodingError:
            return .customError(error.localizedDescription ?? "An unknown error occurred.")
        }
    }

    private var retryOnTimeout: Bool {
        UserDefaults.standard.bool(forKey: "EnhancementRetryOnTimeout")
    }

    private func makeRequestWithRetry(text: String, mode: EnhancementPrompt, configuration: EnhancementRuntimeConfiguration? = nil, maxRetries: Int = 3, initialDelay: TimeInterval = 1.0) async throws -> String {
        var retries = 0
        var currentDelay = initialDelay

        while retries < maxRetries {
            do {
                return try await makeRequest(text: text, mode: mode, configuration: configuration)
            } catch let error as EnhancementError {
                switch error {
                case .networkError, .serverError, .rateLimitExceeded:
                    retries += 1
                    if retries < maxRetries {
                        logger.warning("Request failed, retrying in \(currentDelay, privacy: .public)s... (Attempt \(retries, privacy: .public)/\(maxRetries, privacy: .public))")
                        try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                        currentDelay *= 2
                    } else {
                        logger.error("Request failed after \(maxRetries, privacy: .public) retries.")
                        throw error
                    }
                case .timeout:
                    if retryOnTimeout {
                        retries += 1
                        if retries < maxRetries {
                            logger.warning("Request timed out, retrying immediately... (Attempt \(retries, privacy: .public)/\(maxRetries, privacy: .public))")
                        } else {
                            logger.error("Request timed out after \(maxRetries, privacy: .public) retries.")
                            throw error
                        }
                    } else {
                        logger.error("Request timed out, failing immediately (retry disabled).")
                        throw error
                    }
                default:
                    throw error
                }
            } catch {
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain && [NSURLErrorNotConnectedToInternet, NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost].contains(nsError.code) {
                    retries += 1
                    if retries < maxRetries {
                        logger.warning("Request failed with network error, retrying in \(currentDelay, privacy: .public)s... (Attempt \(retries, privacy: .public)/\(maxRetries, privacy: .public))")
                        try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                        currentDelay *= 2
                    } else {
                        logger.error("Request failed after \(maxRetries, privacy: .public) retries with network error.")
                        throw EnhancementError.networkError
                    }
                } else {
                    throw error
                }
            }
        }

        throw EnhancementError.enhancementFailed
    }

    func enhance(_ text: String) async throws -> (String, TimeInterval, String?) {
        let startTime = Date()
        let enhancementPrompt: EnhancementPrompt = .transcriptionEnhancement
        let promptName = activePrompt?.title

        do {
            let result = try await makeRequestWithRetry(text: text, mode: enhancementPrompt)
            let endTime = Date()
            let duration = endTime.timeIntervalSince(startTime)
            return (result, duration, promptName)
        } catch {
            throw error
        }
    }

    func enhance(_ text: String, configuration: EnhancementRuntimeConfiguration) async throws -> (String, TimeInterval, String?) {
        let startTime = Date()
        let enhancementPrompt: EnhancementPrompt = .transcriptionEnhancement
        let promptName = configuration.prompt?.title

        do {
            let result = try await makeRequestWithRetry(text: text, mode: enhancementPrompt, configuration: configuration)
            let endTime = Date()
            let duration = endTime.timeIntervalSince(startTime)
            return (result, duration, promptName)
        } catch {
            throw error
        }
    }

    func captureScreenContext() async {
        guard CGPreflightScreenCaptureAccess() else {
            return
        }

        if let capturedText = await screenCaptureService.captureAndExtractText() {
            await MainActor.run {
                self.objectWillChange.send()
            }
        }
    }

    func captureClipboardContext() {
        lastCapturedClipboard = NSPasteboard.general.string(forType: .string)
    }
    
    func clearCapturedContexts() {
        lastCapturedClipboard = nil
        screenCaptureService.lastCapturedText = nil
    }

    @discardableResult
    func addPrompt(title: String, promptText: String, icon: PromptIcon = "doc.text.fill", description: String? = nil, triggerWords: [String] = [], useSystemInstructions: Bool = true) -> CustomPrompt {
        let newPrompt = CustomPrompt(title: title, promptText: promptText, icon: icon, description: description, isPredefined: false, triggerWords: triggerWords, useSystemInstructions: useSystemInstructions)
        customPrompts.append(newPrompt)
        if customPrompts.count == 1 {
            selectedPromptId = newPrompt.id
        }
        return newPrompt
    }

    func updatePrompt(_ prompt: CustomPrompt) {
        if let index = customPrompts.firstIndex(where: { $0.id == prompt.id }) {
            customPrompts[index] = prompt
        }
    }

    func deletePrompt(_ prompt: CustomPrompt) {
        customPrompts.removeAll { $0.id == prompt.id }
        if selectedPromptId == prompt.id {
            selectedPromptId = allPrompts.first?.id
        }

        let fallbackPromptId = allPrompts.first?.id.uuidString
        let deletedPromptId = prompt.id.uuidString
        let modeManager = ModeManager.shared
        var updatedConfigurations = modeManager.configurations
        var didUpdateModes = false

        for index in updatedConfigurations.indices where updatedConfigurations[index].selectedPrompt == deletedPromptId {
            updatedConfigurations[index].selectedPrompt = fallbackPromptId
            didUpdateModes = true
        }

        if didUpdateModes {
            modeManager.replaceConfigurations(updatedConfigurations)
        }
    }

    func setActivePrompt(_ prompt: CustomPrompt) {
        selectedPromptId = prompt.id
    }

    private func initializePredefinedPrompts() {
        let predefinedTemplates = PredefinedPrompts.createDefaultPrompts()

        for template in predefinedTemplates {
            if let existingIndex = customPrompts.firstIndex(where: { $0.id == template.id }) {
                var updatedPrompt = customPrompts[existingIndex]
                updatedPrompt = CustomPrompt(
                    id: updatedPrompt.id,
                    title: template.title,
                    promptText: template.promptText,
                    isActive: updatedPrompt.isActive,
                    icon: template.icon,
                    description: template.description,
                    isPredefined: true,
                    triggerWords: updatedPrompt.triggerWords,
                    useSystemInstructions: template.useSystemInstructions
                )
                customPrompts[existingIndex] = updatedPrompt
            } else {
                customPrompts.append(template)
            }
        }
    }
}

enum EnhancementError: Error {
    case notConfigured
    case invalidResponse
    case enhancementFailed
    case networkError
    case serverError
    case rateLimitExceeded
    case timeout
    case customError(String)
}

extension EnhancementError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "AI provider not configured. Please check your API key."
        case .invalidResponse:
            return "Invalid response from AI provider."
        case .enhancementFailed:
            return "AI enhancement failed to process the text."
        case .networkError:
            return "Network connection failed. Check your internet."
        case .serverError:
            return "The AI provider's server encountered an error. Please try again later."
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please try again later."
        case .timeout:
            return "Enhancement request timed out. Check your connection or increase the timeout duration."
        case .customError(let message):
            return message
        }
    }
}
