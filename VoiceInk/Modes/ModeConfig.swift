import Foundation

enum AutoSendKey: String, Codable, CaseIterable {
    case none = "none"
    case enter = "enter"
    case shiftEnter = "shiftEnter"
    case commandEnter = "commandEnter"

    var displayName: String {
        switch self {
        case .none: return String(localized: "None")
        case .enter: return String(localized: "Return (⏎)")
        case .shiftEnter: return String(localized: "Shift + Return (⇧⏎)")
        case .commandEnter: return String(localized: "Command + Return (⌘⏎)")
        }
    }

    var isEnabled: Bool {
        self != .none
    }
}

enum ModeOutputMode: String, Codable, CaseIterable {
    case paste
    case respond
    case customCommand

    var displayName: String {
        switch self {
        case .paste: return String(localized: "Paste")
        case .respond: return String(localized: "Respond")
        case .customCommand: return String(localized: "Custom Command")
        }
    }

    var iconName: String {
        switch self {
        case .paste: return "doc.on.clipboard"
        case .respond: return "text.bubble"
        case .customCommand: return "terminal"
        }
    }

    var usesPasteOptions: Bool {
        self == .paste
    }

    static func choices(canRespond: Bool) -> [ModeOutputMode] {
        canRespond ? [.paste, .respond, .customCommand] : [.paste, .customCommand]
    }
}

struct ModeCustomCommand: Codable, Equatable {
    var command: String

    init(command: String = "") {
        self.command = command
    }

    var trimmedCommand: String? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct ModeConfig: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var icon: ModeIcon
    var appConfigs: [AppConfig]?
    var urlConfigs: [URLConfig]?
    var triggerGroups: [ModeTriggerGroup]?
    var triggerWords: [String] = []
    var isAIEnhancementEnabled: Bool
    var selectedPrompt: String?
    var selectedTranscriptionModelName: String?
    var isRealtimeTranscriptionEnabled: Bool = true
    var selectedLanguage: String?
    var isTextFormattingEnabled: Bool = false
    var useClipboardContext: Bool
    var useSelectedTextContext: Bool
    var useScreenCapture: Bool
    var selectedAIProvider: String?
    var selectedAIModel: String?
    var outputMode: ModeOutputMode = .paste
    var autoSendKey: AutoSendKey = .none
    var customCommand: ModeCustomCommand?
    var isEnabled: Bool = true
    var isDefault: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, name, icon, appConfigs, urlConfigs, triggerGroups, triggerWords, isAIEnhancementEnabled,
            selectedPrompt, isRealtimeTranscriptionEnabled, selectedLanguage, isTextFormattingEnabled,
            useClipboardContext, useSelectedTextContext, useScreenCapture, selectedAIProvider, selectedAIModel,
            outputMode, isAutoSendEnabled, autoSendKey, customCommand, isEnabled, isDefault
        case legacyEmoji = "emoji"
        case selectedWhisperModel
        case selectedTranscriptionModelName
    }

    init(
        id: UUID = UUID(), name: String, icon: ModeIcon = .defaultIcon, appConfigs: [AppConfig]? = nil,
        urlConfigs: [URLConfig]? = nil, triggerGroups: [ModeTriggerGroup]? = nil, triggerWords: [String] = [],
        isAIEnhancementEnabled: Bool, selectedPrompt: String? = nil,
        selectedTranscriptionModelName: String? = nil, isRealtimeTranscriptionEnabled: Bool = true,
        selectedLanguage: String? = nil, useClipboardContext: Bool = false, useSelectedTextContext: Bool = true,
        useScreenCapture: Bool = false,
        isTextFormattingEnabled: Bool = false, selectedAIProvider: String? = nil, selectedAIModel: String? = nil,
        outputMode: ModeOutputMode = .paste, autoSendKey: AutoSendKey = .none, customCommand: ModeCustomCommand? = nil,
        isEnabled: Bool = true, isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.appConfigs = appConfigs
        self.urlConfigs = urlConfigs
        self.triggerGroups = triggerGroups
        self.triggerWords = Self.normalizedTriggerWords(triggerWords)
        self.isAIEnhancementEnabled = isAIEnhancementEnabled
        self.selectedPrompt = selectedPrompt
        self.useClipboardContext = useClipboardContext
        self.useSelectedTextContext = useSelectedTextContext
        self.useScreenCapture = useScreenCapture
        self.autoSendKey = autoSendKey
        self.outputMode = outputMode
        self.customCommand = customCommand
        self.selectedAIProvider = selectedAIProvider
        self.selectedAIModel = selectedAIModel
        self.selectedTranscriptionModelName = selectedTranscriptionModelName
        self.isRealtimeTranscriptionEnabled = isRealtimeTranscriptionEnabled
        self.selectedLanguage = selectedLanguage ?? "en"
        self.isTextFormattingEnabled = isTextFormattingEnabled
        self.isEnabled = isEnabled
        self.isDefault = isDefault
    }

    static func normalizedTriggerWords(_ words: [String]) -> [String] {
        var seen = Set<String>()
        return words.compactMap { word in
            let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return trimmed
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        if let decodedIcon = try container.decodeIfPresent(ModeIcon.self, forKey: .icon) {
            icon = decodedIcon
        } else if let legacyEmoji = try container.decodeIfPresent(String.self, forKey: .legacyEmoji),
            !legacyEmoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            icon = .emoji(legacyEmoji)
        } else {
            icon = .defaultIcon
        }
        appConfigs = try container.decodeIfPresent([AppConfig].self, forKey: .appConfigs)
        urlConfigs = try container.decodeIfPresent([URLConfig].self, forKey: .urlConfigs)
        triggerGroups = try container.decodeIfPresent([ModeTriggerGroup].self, forKey: .triggerGroups)
        triggerWords = Self.normalizedTriggerWords(
            try container.decodeIfPresent([String].self, forKey: .triggerWords) ?? [])
        isAIEnhancementEnabled = try container.decode(Bool.self, forKey: .isAIEnhancementEnabled)
        selectedPrompt = try container.decodeIfPresent(String.self, forKey: .selectedPrompt)
        isRealtimeTranscriptionEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .isRealtimeTranscriptionEnabled) ?? true
        selectedLanguage = try container.decodeIfPresent(String.self, forKey: .selectedLanguage)
        isTextFormattingEnabled = try container.decodeIfPresent(Bool.self, forKey: .isTextFormattingEnabled) ?? false
        useClipboardContext =
            try container.decodeIfPresent(Bool.self, forKey: .useClipboardContext)
            ?? UserDefaults.standard.bool(forKey: "useClipboardContext")
        if let decodedSelectedTextContext = try container.decodeIfPresent(Bool.self, forKey: .useSelectedTextContext) {
            useSelectedTextContext = decodedSelectedTextContext
        } else if UserDefaults.standard.object(forKey: "useSelectedTextContext") == nil {
            useSelectedTextContext = true
        } else {
            useSelectedTextContext = UserDefaults.standard.bool(forKey: "useSelectedTextContext")
        }
        useScreenCapture =
            try container.decodeIfPresent(Bool.self, forKey: .useScreenCapture)
            ?? UserDefaults.standard.bool(forKey: "useScreenCaptureContext")
        selectedAIProvider = try container.decodeIfPresent(String.self, forKey: .selectedAIProvider)
        selectedAIModel = try container.decodeIfPresent(String.self, forKey: .selectedAIModel)
        outputMode = try container.decodeIfPresent(ModeOutputMode.self, forKey: .outputMode) ?? .paste
        customCommand = try container.decodeIfPresent(ModeCustomCommand.self, forKey: .customCommand)
        // Migrate from old isAutoSendEnabled bool to new autoSendKey enum
        if let rawValue = try container.decodeIfPresent(String.self, forKey: .autoSendKey),
            let newKey = AutoSendKey(rawValue: rawValue)
        {
            autoSendKey = newKey
        } else if let oldBool = try container.decodeIfPresent(Bool.self, forKey: .isAutoSendEnabled), oldBool {
            autoSendKey = .enter
        } else {
            autoSendKey = .none
        }
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false

        if let newModelName = try container.decodeIfPresent(String.self, forKey: .selectedTranscriptionModelName) {
            selectedTranscriptionModelName = newModelName
        } else if let oldModelName = try container.decodeIfPresent(String.self, forKey: .selectedWhisperModel) {
            selectedTranscriptionModelName = oldModelName
        } else {
            selectedTranscriptionModelName = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(icon, forKey: .icon)
        try container.encodeIfPresent(appConfigs, forKey: .appConfigs)
        try container.encodeIfPresent(urlConfigs, forKey: .urlConfigs)
        try container.encodeIfPresent(triggerGroups, forKey: .triggerGroups)
        if !triggerWords.isEmpty { try container.encode(triggerWords, forKey: .triggerWords) }
        try container.encode(isAIEnhancementEnabled, forKey: .isAIEnhancementEnabled)
        try container.encodeIfPresent(selectedPrompt, forKey: .selectedPrompt)
        try container.encode(isRealtimeTranscriptionEnabled, forKey: .isRealtimeTranscriptionEnabled)
        try container.encodeIfPresent(selectedLanguage, forKey: .selectedLanguage)
        try container.encode(isTextFormattingEnabled, forKey: .isTextFormattingEnabled)
        try container.encode(useClipboardContext, forKey: .useClipboardContext)
        try container.encode(useSelectedTextContext, forKey: .useSelectedTextContext)
        try container.encode(useScreenCapture, forKey: .useScreenCapture)
        try container.encodeIfPresent(selectedAIProvider, forKey: .selectedAIProvider)
        try container.encodeIfPresent(selectedAIModel, forKey: .selectedAIModel)
        try container.encode(outputMode, forKey: .outputMode)
        try container.encode(autoSendKey, forKey: .autoSendKey)
        try container.encodeIfPresent(customCommand, forKey: .customCommand)
        try container.encodeIfPresent(selectedTranscriptionModelName, forKey: .selectedTranscriptionModelName)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(isDefault, forKey: .isDefault)
    }

    static func == (lhs: ModeConfig, rhs: ModeConfig) -> Bool {
        lhs.id == rhs.id
    }
}

struct AppConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var bundleIdentifier: String
    var appName: String

    init(id: UUID = UUID(), bundleIdentifier: String, appName: String) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
    }

    static func == (lhs: AppConfig, rhs: AppConfig) -> Bool {
        lhs.id == rhs.id
    }
}

struct URLConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var url: String

    init(id: UUID = UUID(), url: String) {
        self.id = id
        self.url = url
    }

    static func == (lhs: URLConfig, rhs: URLConfig) -> Bool {
        lhs.id == rhs.id
    }
}

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

    func addConfiguration(_ config: ModeConfig) {
        if !configurations.contains(where: { $0.id == config.id }) {
            let previousEnabledConfigIds = enabledConfigurationIds
            configurations.append(config)
            saveConfigurations()
            postShortcutAvailabilityChangeIfNeeded(previousEnabledConfigIds: previousEnabledConfigIds)
        }
    }

    func removeConfiguration(with id: UUID) {
        let previousEnabledConfigIds = enabledConfigurationIds
        ShortcutStore.removeShortcutStorage(for: .mode(id))
        configurations.removeAll { $0.id == id }
        saveConfigurations()
        postShortcutAvailabilityChangeIfNeeded(previousEnabledConfigIds: previousEnabledConfigIds)
    }

    func getConfiguration(with id: UUID) -> ModeConfig? {
        return configurations.first { $0.id == id }
    }

    func updateConfiguration(_ config: ModeConfig) {
        if let index = configurations.firstIndex(where: { $0.id == config.id }) {
            let previousEnabledConfigIds = enabledConfigurationIds
            configurations[index] = config
            saveConfigurations()
            postShortcutAvailabilityChangeIfNeeded(previousEnabledConfigIds: previousEnabledConfigIds)
        }
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

    var currentEffectiveConfiguration: ModeConfig? {
        if let activeConfiguration,
            let latestActive = configurations.first(where: { $0.id == activeConfiguration.id }),
            latestActive.isEnabled
        {
            return latestActive
        }

        return getDefaultConfiguration()
    }

    func hasDefaultConfiguration() -> Bool {
        return configurations.contains { $0.isDefault }
    }

    func setAsDefault(configId: UUID, skipSave: Bool = false) {
        for index in configurations.indices {
            configurations[index].isDefault = false
        }

        if let index = configurations.firstIndex(where: { $0.id == configId }) {
            configurations[index].isDefault = true
        }

        if !skipSave {
            saveConfigurations()
        }
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
        if let index = configurations.firstIndex(where: { $0.id == id }) {
            let previousEnabledConfigIds = enabledConfigurationIds
            configurations[index].isEnabled = false
            saveConfigurations()
            postShortcutAvailabilityChangeIfNeeded(previousEnabledConfigIds: previousEnabledConfigIds)
        }
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

        return currentEffectiveConfiguration ?? enabledConfigurations.first
    }

    func resolvedEnabledConfigurationId(preferredId: UUID?) -> UUID? {
        resolvedEnabledConfiguration(preferredId: preferredId)?.id
    }

    private var enabledConfigurationIds: Set<UUID> {
        Set(enabledConfigurations.map(\.id))
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
