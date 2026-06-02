import Foundation

enum StarterModeFactory {
    static let transcriptionModelName = "parakeet-tdt-0.6b-v3"

    static func install(kinds: [StarterModeKind], provider: AIProvider, modelName: String?) {
        let manager = ModeManager.shared
        let requestedKinds = Set(kinds)

        let starterConfigs = StarterModeCatalog.templates
            .filter { requestedKinds.contains($0.kind) }
            .map { makeConfig(from: $0, provider: provider, modelName: modelName) }

        let nonStarterConfigs = manager.configurations
            .filter { !StarterModeCatalog.ids.contains($0.id) }
            .map { config -> ModeConfig in
                var config = config
                if starterConfigs.contains(where: \.isDefault) {
                    config.isDefault = false
                }
                return config
            }

        manager.replaceConfigurations(starterConfigs + nonStarterConfigs)

        for config in starterConfigs where config.isDefault {
            ShortcutStore.removeShortcutStorage(for: .mode(config.id))
        }

        if let defaultConfig = starterConfigs.first(where: \.isDefault) {
            manager.setActiveConfiguration(defaultConfig)
        }
    }

    static func isInstalled(kind: StarterModeKind) -> Bool {
        guard let template = StarterModeCatalog.templates.first(where: { $0.kind == kind }) else {
            return false
        }

        return ModeManager.shared.configurations.contains { $0.id == template.id }
    }

    private static func makeConfig(
        from template: StarterModeTemplate,
        provider: AIProvider,
        modelName: String?
    ) -> ModeConfig {
        ModeConfig(
            id: template.id,
            name: template.name,
            icon: template.icon,
            appConfigs: nil,
            urlConfigs: nil,
            triggerGroups: triggerGroups(for: template.kind),
            isAIEnhancementEnabled: template.usesAIEnhancement,
            selectedPrompt: template.promptId?.uuidString,
            selectedTranscriptionModelName: transcriptionModelName,
            isRealtimeTranscriptionEnabled: true,
            selectedLanguage: "en",
            useClipboardContext: template.kind == .email,
            useSelectedTextContext: template.useSelectedTextContext,
            useScreenCapture: template.useScreenCapture,
            isTextFormattingEnabled: true,
            punctuationCleanupMode: .keep,
            lowercaseTranscription: false,
            selectedAIProvider: template.usesAIEnhancement ? provider.rawValue : nil,
            selectedAIModel: template.usesAIEnhancement ? (modelName ?? provider.defaultModel) : nil,
            outputMode: template.outputMode,
            autoSendKey: .none,
            isEnabled: true,
            isDefault: template.isDefault
        )
    }

    private static func triggerGroups(for kind: StarterModeKind) -> [ModeTriggerGroup]? {
        guard kind == .email,
              let emailTemplate = TriggerTemplateCatalog.templates.first(where: { $0.id == "email" }) else {
            return nil
        }

        let appConfigs = emailTemplate.apps.map { app in
            AppConfig(
                bundleIdentifier: app.bundleIdentifier,
                appName: app.nameHints.first ?? app.bundleIdentifier
            )
        }

        let urlConfigs = emailTemplate.websites.map { URLConfig(url: $0) }

        return [
            ModeTriggerGroup(
                templateId: emailTemplate.id,
                name: emailTemplate.name,
                appConfigs: appConfigs,
                urlConfigs: urlConfigs
            )
        ]
    }

}
