import Foundation

extension ModeManager {
    func migratedModeConfigurationData(for configKey: String) -> Data? {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: configKey) {
            return data
        }

        guard let legacyData = defaults.data(forKey: LegacyModeDataKey.configurations) else {
            return nil
        }

        defaults.set(legacyData, forKey: configKey)
        return legacyData
    }

    func migrateLegacyModeDefaultsIfNeeded() {
        guard configurations.isEmpty || !configurations.contains(where: { $0.isDefault }) else { return }

        let legacyConfig = makeLegacyDefaultConfiguration(
            name: uniqueConfigurationName(base: "Default"),
            isDefault: true
        )

        if configurations.isEmpty {
            configurations = [legacyConfig]
        } else {
            configurations.append(legacyConfig)
        }

        saveConfigurations()
    }

    func migrateLoadedModeConfigurationsIfNeeded() {
        var didChange = false

        for index in configurations.indices {
            var config = configurations[index]
            var changedConfig = false

            if config.selectedTranscriptionModelName == nil {
                config.selectedTranscriptionModelName = UserDefaults.standard.string(forKey: "CurrentTranscriptionModel")
                changedConfig = true
            }

            if config.selectedLanguage == nil {
                config.selectedLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "en"
                changedConfig = true
            }

            if config.selectedAIProvider == nil {
                config.selectedAIProvider = UserDefaults.standard.string(forKey: "selectedAIProvider")
                changedConfig = true
            }

            if config.selectedAIModel == nil,
               let provider = config.selectedAIProvider {
                config.selectedAIModel = UserDefaults.standard.string(forKey: "\(provider)SelectedModel")
                changedConfig = true
            }

            if config.isAIEnhancementEnabled && config.selectedPrompt == nil {
                config.selectedPrompt = UserDefaults.standard.string(forKey: "selectedPromptId")
                changedConfig = true
            }

            if changedConfig {
                configurations[index] = config
                didChange = true
            }
        }

        if didChange {
            saveConfigurations()
        }

        migrateLegacyShortcutStorageIfNeeded()
    }

    private func makeLegacyDefaultConfiguration(name: String, isDefault: Bool) -> ModeConfig {
        let defaults = UserDefaults.standard
        let selectedTextContext: Bool
        if defaults.object(forKey: "useSelectedTextContext") == nil {
            selectedTextContext = true
        } else {
            selectedTextContext = defaults.bool(forKey: "useSelectedTextContext")
        }

        let legacyAIProvider = defaults.string(forKey: "selectedAIProvider")
        let legacyAIModel = legacyAIProvider.flatMap { defaults.string(forKey: "\($0)SelectedModel") }

        return ModeConfig(
            name: name,
            emoji: "✏️",
            isAIEnhancementEnabled: defaults.bool(forKey: "isAIEnhancementEnabled"),
            selectedPrompt: defaults.string(forKey: "selectedPromptId"),
            selectedTranscriptionModelName: defaults.string(forKey: "CurrentTranscriptionModel"),
            selectedLanguage: defaults.string(forKey: "SelectedLanguage") ?? "en",
            useClipboardContext: defaults.bool(forKey: "useClipboardContext"),
            useSelectedTextContext: selectedTextContext,
            useScreenCapture: defaults.bool(forKey: "useScreenCaptureContext"),
            isTextFormattingEnabled: defaults.bool(forKey: "IsTextFormattingEnabled"),
            punctuationCleanupMode: PunctuationCleanupMode.current(),
            lowercaseTranscription: defaults.bool(forKey: "LowercaseTranscription"),
            selectedAIProvider: legacyAIProvider,
            selectedAIModel: legacyAIModel,
            isDefault: isDefault
        )
    }

    private func uniqueConfigurationName(base: String) -> String {
        var candidate = base
        var suffix = 2
        while configurations.contains(where: { $0.name == candidate }) {
            candidate = "\(base) \(suffix)"
            suffix += 1
        }
        return candidate
    }

    private func migrateLegacyShortcutStorageIfNeeded() {
        let defaults = UserDefaults.standard

        for config in configurations {
            let oldShortcutKey = "\(LegacyModeDataKey.shortcutPrefix)\(config.id.uuidString)"
            let newShortcutKey = ShortcutAction.mode(config.id).userDefaultsKey

            if defaults.object(forKey: newShortcutKey) == nil,
               let oldShortcutData = defaults.data(forKey: oldShortcutKey) {
                defaults.set(oldShortcutData, forKey: newShortcutKey)
            }

            let oldClearedKey = "\(oldShortcutKey)_cleared"
            let newClearedKey = "\(newShortcutKey)_cleared"
            if defaults.object(forKey: newClearedKey) == nil,
               defaults.object(forKey: oldClearedKey) != nil {
                defaults.set(defaults.bool(forKey: oldClearedKey), forKey: newClearedKey)
            }
        }
    }
}

private enum LegacyModeDataKey {
    static let configurations = "powerModeConfigurationsV2"
    static let shortcutPrefix = "Shortcut_powerMode_"
}
