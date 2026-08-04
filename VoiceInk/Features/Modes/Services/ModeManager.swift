import Foundation
import SwiftUI

class ModeManager: ObservableObject {
    static let shared = ModeManager()
    @Published var configurations: [ModeConfig] = []
    @Published var activeConfiguration: ModeConfig?

    private let configKey = "modeConfigurationsV2"
    private let activeConfigIdKey = "activeConfigurationId"

    private init() {
        loadConfigurations()

        if let activeConfigIdString = UserDefaults.standard.string(forKey: activeConfigIdKey),
            let activeConfigId = UUID(uuidString: activeConfigIdString)
        {
            activeConfiguration = configurations.first { $0.id == activeConfigId }
        } else {
            activeConfiguration = nil
        }
    }

    private func loadConfigurations() {
        if let data = migratedModeConfigurationData(for: configKey),
            let configs = try? JSONDecoder().decode([ModeConfig].self, from: data)
        {
            configurations = configs
            migrateLoadedModeConfigurationsIfNeeded()
        }
    }

    func saveConfigurations() {
        if let data = try? JSONEncoder().encode(configurations) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
        NotificationCenter.default.post(name: .modeConfigurationsDidChange, object: nil)
    }

    func addConfiguration(_ newConfiguration: ModeConfig) {
        guard !configurations.contains(where: { $0.id == newConfiguration.id }) else {
            return
        }

        let previousEnabledConfigIds = enabledConfigurationIds
        var configuration = newConfiguration
        if configuration.isDefault {
            for index in configurations.indices {
                configurations[index].isDefault = false
            }
            configuration.isEnabled = true
        }

        configurations.append(configuration)
        saveConfigurations()
        postShortcutAvailabilityChangeIfNeeded(previousEnabledConfigIds: previousEnabledConfigIds)
    }

    func removeConfiguration(with id: UUID) -> ModeRemovalResult {
        guard let configuration = getConfiguration(with: id) else {
            return .notFound
        }
        guard !configuration.isDefault else {
            return .blockedDefault
        }

        let previousEffectiveConfigurationId = currentEffectiveConfiguration?.id
        let previousEnabledConfigIds = enabledConfigurationIds
        ShortcutStore.removeShortcutStorage(for: .mode(id))
        configurations.removeAll { $0.id == id }
        let selectedConfiguration = repairActiveConfigurationIfNeeded(
            previousEffectiveConfigurationId: previousEffectiveConfigurationId
        )
        saveConfigurations()
        postShortcutAvailabilityChangeIfNeeded(previousEnabledConfigIds: previousEnabledConfigIds)
        notifyActiveConfigurationChange(selectedConfiguration)
        return .removed
    }

    func getConfiguration(with id: UUID) -> ModeConfig? {
        return configurations.first { $0.id == id }
    }

    func updateConfiguration(_ updatedConfiguration: ModeConfig) {
        guard let index = configurations.firstIndex(where: { $0.id == updatedConfiguration.id }) else {
            return
        }

        let previousEnabledConfigIds = enabledConfigurationIds
        var configuration = updatedConfiguration
        if configuration.isDefault {
            for configurationIndex in configurations.indices {
                configurations[configurationIndex].isDefault = false
            }
            configuration.isEnabled = true
        }

        configurations[index] = configuration
        saveConfigurations()
        postShortcutAvailabilityChangeIfNeeded(previousEnabledConfigIds: previousEnabledConfigIds)
    }

    func moveConfigurations(fromOffsets: IndexSet, toOffset: Int) {
        var updatedConfigurations = configurations
        updatedConfigurations.move(fromOffsets: fromOffsets, toOffset: toOffset)
        replaceConfigurations(updatedConfigurations)
    }

    func replaceConfigurations(_ updatedConfigurations: [ModeConfig]) {
        let previousEnabledConfigIds = enabledConfigurationIds
        configurations = updatedConfigurations
        saveConfigurations()
        postShortcutAvailabilityChangeIfNeeded(previousEnabledConfigIds: previousEnabledConfigIds)
    }

    func getConfigurationForURL(_ url: String) -> ModeConfig? {
        let cleanedURL = cleanURL(url)

        for config in configurations.filter({ $0.isEnabled }) {
            for urlConfig in config.allURLConfigs {
                let configURL = cleanURL(urlConfig.url)

                if cleanedURL.contains(configURL) {
                    return config
                }
            }
        }
        return nil
    }

    func getConfigurationForApp(_ bundleId: String) -> ModeConfig? {
        for config in configurations.filter({ $0.isEnabled }) {
            if config.allAppConfigs.contains(where: { $0.bundleIdentifier == bundleId }) {
                return config
            }
        }
        return nil
    }

    func getDefaultConfiguration() -> ModeConfig? {
        return configurations.first { $0.isEnabled && $0.isDefault }
    }

    /// The single source of truth for which mode is running, for UI and pipeline alike.
    var currentEffectiveConfiguration: ModeConfig? {
        if let activeConfiguration,
            let latestActive = configurations.first(where: { $0.id == activeConfiguration.id }),
            latestActive.isEnabled
        {
            return latestActive
        }

        return getDefaultConfiguration() ?? enabledConfigurations.first
    }

    func hasDefaultConfiguration() -> Bool {
        return configurations.contains { $0.isDefault }
    }

    func setAsDefault(configId: UUID, skipSave: Bool = false) {
        guard let targetIndex = configurations.firstIndex(where: { $0.id == configId }) else {
            return
        }

        let previousEnabledConfigIds = enabledConfigurationIds

        for index in configurations.indices {
            configurations[index].isDefault = false
        }

        configurations[targetIndex].isDefault = true
        configurations[targetIndex].isEnabled = true

        if !skipSave {
            saveConfigurations()
        }
        postShortcutAvailabilityChangeIfNeeded(previousEnabledConfigIds: previousEnabledConfigIds)
    }

    func enableConfiguration(with id: UUID) {
        if let index = configurations.firstIndex(where: { $0.id == id }) {
            let previousEnabledConfigIds = enabledConfigurationIds
            configurations[index].isEnabled = true
            saveConfigurations()
            postShortcutAvailabilityChangeIfNeeded(previousEnabledConfigIds: previousEnabledConfigIds)
        }
    }

    func disableConfiguration(with id: UUID) {
        guard let index = configurations.firstIndex(where: { $0.id == id }),
            configurations[index].isEnabled,
            !configurations[index].isDefault
        else {
            return
        }

        let previousEffectiveConfigurationId = currentEffectiveConfiguration?.id
        let previousEnabledConfigIds = enabledConfigurationIds
        configurations[index].isEnabled = false
        let selectedConfiguration = repairActiveConfigurationIfNeeded(
            previousEffectiveConfigurationId: previousEffectiveConfigurationId
        )
        saveConfigurations()
        postShortcutAvailabilityChangeIfNeeded(previousEnabledConfigIds: previousEnabledConfigIds)
        notifyActiveConfigurationChange(selectedConfiguration)
    }

    var enabledConfigurations: [ModeConfig] {
        return configurations.filter { $0.isEnabled }
    }

    func resolvedEnabledConfiguration(preferredId: UUID?) -> ModeConfig? {
        if let preferredId,
            let configuration = enabledConfigurations.first(where: { $0.id == preferredId })
        {
            return configuration
        }

        return currentEffectiveConfiguration
    }

    func resolvedEnabledConfigurationId(preferredId: UUID?) -> UUID? {
        resolvedEnabledConfiguration(preferredId: preferredId)?.id
    }

    var hasEnabledConfiguration: Bool {
        configurations.contains(where: \.isEnabled)
    }

    private var enabledConfigurationIds: Set<UUID> {
        Set(enabledConfigurations.map(\.id))
    }

    /// Repairs an invalid active selection using enabled modes only.
    private func repairActiveConfigurationIfNeeded(
        previousEffectiveConfigurationId: UUID?
    ) -> ModeConfig? {
        let enabledConfigIds = enabledConfigurationIds
        let activeConfigurationIsUnavailable =
            activeConfiguration.map { active in
                !enabledConfigIds.contains(active.id)
            } ?? false
        let previousEffectiveConfigurationIsUnavailable =
            previousEffectiveConfigurationId.map { id in
                !enabledConfigIds.contains(id)
            } ?? false

        guard activeConfigurationIsUnavailable || previousEffectiveConfigurationIsUnavailable else {
            return nil
        }

        guard let target = getDefaultConfiguration() ?? enabledConfigurations.first else {
            setActiveConfiguration(nil)
            return nil
        }

        setActiveConfiguration(target)
        return target.id == previousEffectiveConfigurationId ? nil : target
    }

    private func notifyActiveConfigurationChange(_ config: ModeConfig?) {
        guard let config else { return }

        Task { @MainActor in
            NotificationManager.shared.showNotification(
                title: String(
                    format: String(localized: "Active mode switched to %@"),
                    config.name
                ),
                type: .info
            )
        }
    }

    private func postShortcutAvailabilityChangeIfNeeded(previousEnabledConfigIds: Set<UUID>) {
        guard previousEnabledConfigIds != enabledConfigurationIds else {
            return
        }

        NotificationCenter.default.post(name: .modeShortcutAvailabilityDidChange, object: nil)
    }

    func addAppConfig(_ appConfig: AppConfig, to config: ModeConfig) {
        if var updatedConfig = configurations.first(where: { $0.id == config.id }) {
            var configs = updatedConfig.appConfigs ?? []
            configs.append(appConfig)
            updatedConfig.appConfigs = configs
            updateConfiguration(updatedConfig)
        }
    }

    func removeAppConfig(_ appConfig: AppConfig, from config: ModeConfig) {
        if var updatedConfig = configurations.first(where: { $0.id == config.id }) {
            updatedConfig.appConfigs?.removeAll(where: { $0.id == appConfig.id })
            updateConfiguration(updatedConfig)
        }
    }

    func addURLConfig(_ urlConfig: URLConfig, to config: ModeConfig) {
        if var updatedConfig = configurations.first(where: { $0.id == config.id }) {
            var configs = updatedConfig.urlConfigs ?? []
            configs.append(urlConfig)
            updatedConfig.urlConfigs = configs
            updateConfiguration(updatedConfig)
        }
    }

    func removeURLConfig(_ urlConfig: URLConfig, from config: ModeConfig) {
        if var updatedConfig = configurations.first(where: { $0.id == config.id }) {
            updatedConfig.urlConfigs?.removeAll(where: { $0.id == urlConfig.id })
            updateConfiguration(updatedConfig)
        }
    }

    func getConfigurationForTriggerWord(_ text: String) -> (mode: ModeConfig, processedText: String)? {
        guard
            let detection = ModeTriggerWordDetectionService.detect(
                in: text,
                configurations: configurations.filter { $0.isEnabled }
            )
        else { return nil }
        return (detection.mode, detection.processedText)
    }

    func cleanURL(_ url: String) -> String {
        return url.lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func setActiveConfiguration(_ config: ModeConfig?) {
        if let config,
            let latestConfig = configurations.first(where: { $0.id == config.id })
        {
            activeConfiguration = latestConfig
        } else {
            activeConfiguration = config
        }
        UserDefaults.standard.set(config?.id.uuidString, forKey: activeConfigIdKey)
        self.objectWillChange.send()
    }

    func updateCurrentEffectiveConfiguration(_ update: (inout ModeConfig) -> Void) {
        guard var config = currentEffectiveConfiguration else { return }
        update(&config)
        updateConfiguration(config)

        if activeConfiguration?.id == config.id {
            activeConfiguration = config
        }
    }

    var currentActiveConfiguration: ModeConfig? {
        return activeConfiguration
    }

    func getAllAvailableConfigurations() -> [ModeConfig] {
        return configurations
    }

    func isEmojiInUse(_ emoji: String) -> Bool {
        return configurations.contains { $0.icon == .emoji(emoji) }
    }
}

