import Foundation

struct PowerModeConfigDraft {
    var id: UUID
    var name: String
    var emoji: String
    var appConfigs: [AppConfig]
    var websiteConfigs: [URLConfig]
    var isAIEnhancementEnabled: Bool
    var selectedPromptId: UUID?
    var selectedTranscriptionModelName: String?
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
    var isTranscriptFormattingExpanded: Bool

    private var sourceConfig: PowerModeConfig?

    private static var defaultSelectedTextContext: Bool {
        if UserDefaults.standard.object(forKey: "useSelectedTextContext") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "useSelectedTextContext")
    }

    init(mode: ConfigurationMode, powerModeManager: PowerModeManager) {
        switch mode {
        case .add:
            id = UUID()
            name = ""
            emoji = "✏️"
            appConfigs = []
            websiteConfigs = []
            isAIEnhancementEnabled = false
            selectedPromptId = nil
            selectedTranscriptionModelName = nil
            selectedLanguage = nil
            isTextFormattingEnabled = false
            punctuationCleanupMode = .keep
            lowercaseTranscription = false
            useClipboardContext = UserDefaults.standard.bool(forKey: "useClipboardContext")
            useSelectedTextContext = Self.defaultSelectedTextContext
            useScreenCapture = false
            selectedAIProvider = UserDefaults.standard.string(forKey: "selectedAIProvider")
            selectedAIModel = nil
            autoSendKey = .none
            isDefault = false
            isTranscriptFormattingExpanded = false
            sourceConfig = nil

        case .edit(let config):
            let latestConfig = powerModeManager.getConfiguration(with: config.id) ?? config
            id = latestConfig.id
            name = latestConfig.name
            emoji = latestConfig.emoji
            appConfigs = latestConfig.appConfigs ?? []
            websiteConfigs = latestConfig.urlConfigs ?? []
            isAIEnhancementEnabled = latestConfig.isAIEnhancementEnabled
            selectedPromptId = latestConfig.selectedPrompt.flatMap { UUID(uuidString: $0) }
            selectedTranscriptionModelName = latestConfig.selectedTranscriptionModelName
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
            isTranscriptFormattingExpanded = latestConfig.isTextFormattingEnabled ||
                latestConfig.punctuationCleanupMode != .keep ||
                latestConfig.lowercaseTranscription
            sourceConfig = latestConfig
        }
    }

    var canSave: Bool {
        !name.isEmpty
    }

    func effectiveModelName(fallback: String?) -> String? {
        selectedTranscriptionModelName ?? fallback
    }

    mutating func applyAddModeDefaults(aiService: AIService) {
        if selectedAIProvider == nil {
            selectedAIProvider = aiService.selectedProvider.rawValue
        }
        if selectedAIModel == nil || selectedAIModel?.isEmpty == true {
            selectedAIModel = aiService.currentModel
        }
    }

    mutating func ensurePromptSelection(firstPromptId: UUID?) {
        if isAIEnhancementEnabled && selectedPromptId == nil {
            selectedPromptId = firstPromptId
        }
    }

    mutating func useCompatibleLanguage(for model: any TranscriptionModel) {
        selectedLanguage = TranscriptionLanguageSupport.validLanguageOrFallback(
            selectedLanguage ?? UserDefaults.standard.string(forKey: "SelectedLanguage"),
            for: model
        )
    }

    func makeConfig(mode: ConfigurationMode) -> PowerModeConfig {
        switch mode {
        case .add:
            return PowerModeConfig(
                id: id,
                name: name,
                emoji: emoji,
                appConfigs: appConfigs.isEmpty ? nil : appConfigs,
                urlConfigs: websiteConfigs.isEmpty ? nil : websiteConfigs,
                isAIEnhancementEnabled: isAIEnhancementEnabled,
                selectedPrompt: selectedPromptId?.uuidString,
                selectedTranscriptionModelName: selectedTranscriptionModelName,
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
            updatedConfig.emoji = emoji
            updatedConfig.appConfigs = appConfigs.isEmpty ? nil : appConfigs
            updatedConfig.urlConfigs = websiteConfigs.isEmpty ? nil : websiteConfigs
            updatedConfig.isAIEnhancementEnabled = isAIEnhancementEnabled
            updatedConfig.selectedPrompt = selectedPromptId?.uuidString
            updatedConfig.selectedTranscriptionModelName = selectedTranscriptionModelName
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
