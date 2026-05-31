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
    var outputMode: ModeOutputMode
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
            outputMode = .paste
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
            outputMode = latestConfig.outputMode
            autoSendKey = latestConfig.autoSendKey
            isDefault = latestConfig.isDefault
            isTranscriptionFormattingExpanded = false
            sourceConfig = latestConfig
        }
    }

    var canSave: Bool {
        !name.isEmpty
    }

    mutating func applyAddModeDefaults(snapshot: ModeFormWarmupSnapshot) {
        let connectedProviders = snapshot.connectedAIProviders
        let inheritedProvider = selectedAIProvider.flatMap(AIProvider.init(rawValue:))
        let provider = inheritedProvider.flatMap { provider in
            connectedProviders.contains(provider) ? provider : nil
        } ?? connectedProviders.first

        selectedAIProvider = provider?.rawValue
        guard let provider, provider != .localCLI else {
            selectedAIModel = nil
            return
        }

        let availableModels = snapshot.availableModels(for: provider)
        if let selectedAIModel,
           !selectedAIModel.isEmpty,
           (availableModels.isEmpty || availableModels.contains(selectedAIModel)) {
            return
        }

        selectedAIModel = snapshot.selectedModel(for: provider)
    }

    mutating func inheritUsableTranscriptionModelSelection(from snapshot: ModeFormWarmupSnapshot) {
        if let selectedTranscriptionModelName,
           snapshot.hasUsableTranscriptionModel(named: selectedTranscriptionModelName) {
            return
        }

        selectedTranscriptionModelName = snapshot.usableTranscriptionModels.first?.name
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

    mutating func applyOutputRules(canRespond: Bool) {
        if outputMode == .respond && !canRespond {
            outputMode = .paste
        }

        if !outputMode.usesPasteOptions {
            autoSendKey = .none
            isDefault = false
        }
    }

    func makeConfig(mode: ConfigurationMode) -> ModeConfig {
        let savedAutoSendKey: AutoSendKey = outputMode.usesPasteOptions ? autoSendKey : .none
        let savedIsDefault = outputMode.usesPasteOptions ? isDefault : false

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
                outputMode: outputMode,
                autoSendKey: savedAutoSendKey,
                isDefault: savedIsDefault
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
            updatedConfig.outputMode = outputMode
            updatedConfig.autoSendKey = savedAutoSendKey
            updatedConfig.isDefault = savedIsDefault
            return updatedConfig
        }
    }
}
