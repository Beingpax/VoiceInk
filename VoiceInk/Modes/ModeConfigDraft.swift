import Foundation

struct ModeConfigDraft {
    var id: UUID
    var name: String
    var icon: ModeIcon
    var appConfigs: [AppConfig]
    var websiteConfigs: [URLConfig]
    var triggerGroups: [ModeTriggerGroup]
    var isAIEnhancementEnabled: Bool
    var selectedPromptId: UUID?
    var selectedTranscriptionModelName: String?
    var isRealtimeTranscriptionEnabled: Bool
    var selectedLanguage: String?
    var isTextFormattingEnabled: Bool
    var punctuationCleanupMode: PunctuationCleanupMode
    var lowercaseTranscription: Bool
    var useClipboardContext: Bool
    var useSelectedTextContext: Bool
    var useScreenCapture: Bool
    var selectedAIProvider: String?
    var selectedAIModel: String?
    var autoSendKey: AutoSendKey
    var isDefault: Bool
    var isTranscriptionFormattingExpanded: Bool

    private var sourceConfig: ModeConfig?

    init(mode: ConfigurationMode, modeManager: ModeManager) {
        switch mode {
        case .add:
            let inheritedConfig = modeManager.currentEffectiveConfiguration

            id = UUID()
            name = ""
            icon = .defaultIcon
            appConfigs = []
            websiteConfigs = []
            triggerGroups = []
            isAIEnhancementEnabled = false
            selectedPromptId = inheritedConfig?.selectedPrompt.flatMap { UUID(uuidString: $0) }
            selectedTranscriptionModelName = inheritedConfig?.selectedTranscriptionModelName
            isRealtimeTranscriptionEnabled = true
            selectedLanguage = inheritedConfig?.selectedLanguage
            isTextFormattingEnabled = true
            punctuationCleanupMode = .keep
            lowercaseTranscription = false
            useClipboardContext = false
            useSelectedTextContext = false
            useScreenCapture = true
            selectedAIProvider = inheritedConfig?.selectedAIProvider
            selectedAIModel = inheritedConfig?.selectedAIModel
            autoSendKey = .none
            isDefault = false
            isTranscriptionFormattingExpanded = false
            sourceConfig = nil

        case .edit(let config):
            let latestConfig = modeManager.getConfiguration(with: config.id) ?? config
            id = latestConfig.id
            name = latestConfig.name
            icon = latestConfig.icon
            appConfigs = latestConfig.appConfigs ?? []
            websiteConfigs = latestConfig.urlConfigs ?? []
            triggerGroups = latestConfig.triggerGroups ?? []
            isAIEnhancementEnabled = latestConfig.isAIEnhancementEnabled
            selectedPromptId = latestConfig.selectedPrompt.flatMap { UUID(uuidString: $0) }
            selectedTranscriptionModelName = latestConfig.selectedTranscriptionModelName
            isRealtimeTranscriptionEnabled = latestConfig.isRealtimeTranscriptionEnabled
            selectedLanguage = latestConfig.selectedLanguage
            isTextFormattingEnabled = latestConfig.isTextFormattingEnabled
            punctuationCleanupMode = latestConfig.punctuationCleanupMode
            lowercaseTranscription = latestConfig.lowercaseTranscription
            useClipboardContext = latestConfig.useClipboardContext
            useSelectedTextContext = latestConfig.useSelectedTextContext
            useScreenCapture = latestConfig.useScreenCapture
            selectedAIProvider = latestConfig.selectedAIProvider
            selectedAIModel = latestConfig.selectedAIModel
            autoSendKey = latestConfig.autoSendKey
            isDefault = latestConfig.isDefault
            isTranscriptionFormattingExpanded = latestConfig.isTextFormattingEnabled ||
                latestConfig.punctuationCleanupMode != .keep ||
                latestConfig.lowercaseTranscription
            sourceConfig = latestConfig
        }
    }

    var canSave: Bool {
        !name.isEmpty
    }

    mutating func applyAddModeDefaults(aiService: AIService) {
        let connectedProviders = aiService.connectedProviders
        let inheritedProvider = selectedAIProvider.flatMap(AIProvider.init(rawValue:))
        let provider = inheritedProvider.flatMap { provider in
            connectedProviders.contains(provider) ? provider : nil
        } ?? connectedProviders.first

        selectedAIProvider = provider?.rawValue
        guard let provider, provider != .localCLI else {
            selectedAIModel = nil
            return
        }

        let availableModels = aiService.availableModels(for: provider)
        if let selectedAIModel,
           !selectedAIModel.isEmpty,
           (availableModels.isEmpty || availableModels.contains(selectedAIModel)) {
            return
        }

        selectedAIModel = aiService.selectedModel(for: provider)
    }

    mutating func inheritUsableTranscriptionModelSelection(from usableModels: [any TranscriptionModel]) {
        if let selectedTranscriptionModelName,
           usableModels.contains(where: { $0.name == selectedTranscriptionModelName }) {
            return
        }

        selectedTranscriptionModelName = usableModels.first?.name
    }

    mutating func ensureTranscriptionModelSelection(fallback: String?) {
        if selectedTranscriptionModelName == nil {
            selectedTranscriptionModelName = fallback
        }
    }

    mutating func ensurePromptSelection(firstPromptId: UUID?) {
        if isAIEnhancementEnabled && selectedPromptId == nil {
            selectedPromptId = firstPromptId
        }
    }

    mutating func useCompatibleLanguage(for model: any TranscriptionModel) {
        selectedLanguage = TranscriptionLanguageSupport.validLanguageOrFallback(
            selectedLanguage ?? "en",
            for: model,
            realtimeEnabled: isRealtimeTranscriptionEnabled
        )
    }

    func makeConfig(mode: ConfigurationMode) -> ModeConfig {
        switch mode {
        case .add:
            return ModeConfig(
                id: id,
                name: name,
                icon: icon,
                appConfigs: appConfigs.isEmpty ? nil : appConfigs,
                urlConfigs: websiteConfigs.isEmpty ? nil : websiteConfigs,
                triggerGroups: triggerGroups.isEmpty ? nil : triggerGroups,
                isAIEnhancementEnabled: isAIEnhancementEnabled,
                selectedPrompt: selectedPromptId?.uuidString,
                selectedTranscriptionModelName: selectedTranscriptionModelName,
                isRealtimeTranscriptionEnabled: isRealtimeTranscriptionEnabled,
                selectedLanguage: selectedLanguage,
                useClipboardContext: useClipboardContext,
                useSelectedTextContext: useSelectedTextContext,
                useScreenCapture: useScreenCapture,
                isTextFormattingEnabled: isTextFormattingEnabled,
                punctuationCleanupMode: punctuationCleanupMode,
                lowercaseTranscription: lowercaseTranscription,
                selectedAIProvider: selectedAIProvider,
                selectedAIModel: selectedAIModel,
                autoSendKey: autoSendKey,
                isDefault: isDefault
            )

        case .edit(let config):
            var updatedConfig = sourceConfig ?? config
            updatedConfig.name = name
            updatedConfig.icon = icon
            updatedConfig.appConfigs = appConfigs.isEmpty ? nil : appConfigs
            updatedConfig.urlConfigs = websiteConfigs.isEmpty ? nil : websiteConfigs
            updatedConfig.triggerGroups = triggerGroups.isEmpty ? nil : triggerGroups
            updatedConfig.isAIEnhancementEnabled = isAIEnhancementEnabled
            updatedConfig.selectedPrompt = selectedPromptId?.uuidString
            updatedConfig.selectedTranscriptionModelName = selectedTranscriptionModelName
            updatedConfig.isRealtimeTranscriptionEnabled = isRealtimeTranscriptionEnabled
            updatedConfig.selectedLanguage = selectedLanguage
            updatedConfig.isTextFormattingEnabled = isTextFormattingEnabled
            updatedConfig.punctuationCleanupMode = punctuationCleanupMode
            updatedConfig.lowercaseTranscription = lowercaseTranscription
            updatedConfig.useClipboardContext = useClipboardContext
            updatedConfig.useSelectedTextContext = useSelectedTextContext
            updatedConfig.useScreenCapture = useScreenCapture
            updatedConfig.selectedAIProvider = selectedAIProvider
            updatedConfig.selectedAIModel = selectedAIModel
            updatedConfig.autoSendKey = autoSendKey
            updatedConfig.isDefault = isDefault
            return updatedConfig
        }
    }
}
