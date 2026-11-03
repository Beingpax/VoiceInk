import Foundation
import os

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
    var autoSendKey: FinishAndSendKey = .none
    var customCommand: ModeCustomCommand?
    var isEnabled: Bool = true
    var isDefault: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, name, icon, appConfigs, urlConfigs, triggerGroups, triggerWords, isAIEnhancementEnabled,
            selectedPrompt, isRealtimeTranscriptionEnabled, selectedLanguage, isTextFormattingEnabled,
            useClipboardContext, useSelectedTextContext, useScreenCapture, selectedAIProvider, selectedAIModel,
            outputMode, autoSendKey, isAutoSendEnabled, customCommand, isEnabled, isDefault
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
        outputMode: ModeOutputMode = .paste, autoSendKey: FinishAndSendKey = .none,
        customCommand: ModeCustomCommand? = nil,
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
        self.outputMode = outputMode
        self.autoSendKey = autoSendKey
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
        // Keep compatibility with saved modes from before Auto Send became global.
        if let rawValue = try container.decodeIfPresent(String.self, forKey: .autoSendKey),
            let key = FinishAndSendKey(rawValue: rawValue)
        {
            autoSendKey = key
        } else if try container.decodeIfPresent(Bool.self, forKey: .isAutoSendEnabled) == true {
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

enum ModeRemovalResult {
    case removed
    case blockedDefault
    case notFound
}

class ModeManager: ObservableObject {
    static let shared = ModeManager()
    @Published var configurations: [ModeConfig] = []
    @Published var activeConfiguration: ModeConfig?

    private let triggerLogger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "mode.triggers")

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

    @discardableResult
    func duplicateConfiguration(with id: UUID) -> ModeConfig? {
        guard let index = configurations.firstIndex(where: { $0.id == id }) else { return nil }

        let source = configurations[index]
        var duplicate = source
        duplicate.id = UUID()
        duplicate.name = nextDuplicateName(for: source.name)
        duplicate.isDefault = false

        // The new mode keeps the settings, but claims no automatic triggers.
        duplicate.appConfigs = nil
        duplicate.urlConfigs = nil
        duplicate.triggerGroups = nil
        duplicate.triggerWords = []

        // Shortcuts are keyed by mode ID, so the duplicate starts without a shortcut.
        let previousEnabledConfigIds = enabledConfigurationIds
        configurations.insert(duplicate, at: index + 1)
        saveConfigurations()
        postShortcutAvailabilityChangeIfNeeded(previousEnabledConfigIds: previousEnabledConfigIds)
        return duplicate
    }

    private func nextDuplicateName(for name: String) -> String {
        let names = Set(configurations.map(\.name))
        var base = name
        if let separator = name.lastIndex(of: " "),
            let suffix = Int(name[name.index(after: separator)...]),
            suffix > 0,
            names.contains(String(name[..<separator]))
        {
            base = String(name[..<separator])
        }

        var number = 1
        while names.contains("\(base) \(number)") {
            number += 1
        }
        return "\(base) \(number)"
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

    /// Captures rule order as well as disabled rules, which matching deliberately skips.
    func logTriggerRules(diagnosticID: String) {
        triggerLogger.notice(
            "Mode rules id=\(diagnosticID, privacy: .public) count=\(self.configurations.count, privacy: .public) precedence=explicit-mode,website,app,default first-match-wins=true"
        )
        for (index, config) in configurations.enumerated() {
            let apps = config.allAppConfigs.map { $0.bundleIdentifier }.joined(separator: ",")
            let websites = config.allURLConfigs.map { $0.url }.joined(separator: ",")
            triggerLogger.notice(
                "Mode rule id=\(diagnosticID, privacy: .public) order=\(index, privacy: .public) mode=\(config.id.uuidString, privacy: .public) name=\(config.name, privacy: .private) enabled=\(config.isEnabled, privacy: .public) default=\(config.isDefault, privacy: .public) apps=\(apps, privacy: .public) websites=\(websites, privacy: .private)"
            )
        }
    }

    func getConfigurationForURL(_ url: String, diagnosticID: String? = nil) -> ModeConfig? {
        guard let target = Self.target(ofBrowserURL: url) else {
            if let diagnosticID {
                triggerLogger.notice("Website detection id=\(diagnosticID, privacy: .public) result=invalid-or-hostless-url url=\(url, privacy: .private)")
            }
            return nil
        }
        if let diagnosticID {
            let port = target.port.map { String($0) } ?? "unspecified"
            triggerLogger.notice(
                "Website detection id=\(diagnosticID, privacy: .public) host=\(target.host, privacy: .private) port=\(port, privacy: .public) path=\(target.path, privacy: .private) policy=domain-or-subdomain,path-segment-prefix,case-insensitive,explicit-port"
            )
        }

        var checked = 0
        for config in configurations.filter({ $0.isEnabled }) {
            for (index, urlConfig) in config.allURLConfigs.enumerated() {
                let normalizedTrigger = cleanURL(urlConfig.url)
                let reason = Self.triggerMismatchReason(normalizedTrigger, target: target)
                let containsQueryOrFragment = normalizedTrigger.contains("?") || normalizedTrigger.contains("#")
                checked += 1
                if let diagnosticID {
                    triggerLogger.notice(
                        "Website rule id=\(diagnosticID, privacy: .public) mode=\(config.id.uuidString, privacy: .public) rule=\(index, privacy: .public) trigger=\(urlConfig.url, privacy: .private) normalizedTrigger=\(normalizedTrigger, privacy: .private) queryOrFragmentInTrigger=\(containsQueryOrFragment, privacy: .public) result=\(reason ?? "matched", privacy: .public)"
                    )
                }
                if reason == nil {
                    return config
                }
            }
        }
        if let diagnosticID {
            triggerLogger.notice("Website detection id=\(diagnosticID, privacy: .public) result=no-match rulesChecked=\(checked, privacy: .public)")
        }
        return nil
    }

    /// Host, port and path of the active tab. The host is lowercased and loses a
    /// leading "www.". Triggers are stored without a scheme, so a bare host is
    /// parsed as one.
    static func target(ofBrowserURL url: String) -> (host: String, port: Int?, path: String)? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let absolute = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let components = URLComponents(string: absolute),
            let host = components.host,
            !host.isEmpty
        else {
            return nil
        }

        return (normalizedHost(host), components.port, components.path)
    }

    /// A trigger matches the host itself or any subdomain of it. A trigger that
    /// carries a path, such as "icloud.com/mail", also has to match that path
    /// prefix on a segment boundary. Triggers are stored lowercased, so paths
    /// are compared without regard to case.
    static func trigger(_ trigger: String, matches target: (host: String, port: Int?, path: String)) -> Bool {
        triggerMismatchReason(trigger, target: target) == nil
    }

    /// Nil means a match. The same decision supplies diagnostics so reasons cannot drift from matching.
    private static func triggerMismatchReason(_ trigger: String, target: (host: String, port: Int?, path: String)) -> String? {
        let parts = trigger.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first else { return "empty-trigger" }

        let authority = String(first)
        let triggerHost = normalizedHost(authority)
        guard !triggerHost.isEmpty else { return "empty-trigger-host" }
        guard target.host == triggerHost || target.host.hasSuffix("." + triggerHost) else { return "host-mismatch" }

        // A trigger that names a port only matches that port. A trigger whose
        // port is not a number matches nothing rather than every port.
        switch port(ofAuthority: authority) {
        case .absent: break
        case .malformed: return "malformed-trigger-port"
        case .number(let triggerPort): if target.port != triggerPort { return "port-mismatch" }
        }

        guard parts.count > 1 else { return nil }
        // URLComponents reports a decoded path, so decode the trigger as well.
        let rawTriggerPath = String(parts[1])
        let triggerPath = (rawTriggerPath.removingPercentEncoding ?? rawTriggerPath)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        guard !triggerPath.isEmpty else { return nil }

        let prefix = "/" + triggerPath
        let path = target.path.lowercased()
        return path == prefix || path.hasPrefix(prefix + "/") ? nil : "path-mismatch"
    }

    private enum TriggerPort {
        case absent
        case number(Int)
        case malformed
    }

    /// The port of a stored trigger. An IPv6 literal without a bracketed port
    /// carries colons of its own and counts as portless.
    private static func port(ofAuthority authority: String) -> TriggerPort {
        let suffix: Substring
        if authority.hasPrefix("[") {
            guard let closingBracket = authority.firstIndex(of: "]") else { return .malformed }
            let rest = authority[authority.index(after: closingBracket)...]
            guard rest.hasPrefix(":") else { return rest.isEmpty ? .absent : .malformed }
            suffix = rest.dropFirst()
        } else {
            guard authority.filter({ $0 == ":" }).count == 1,
                let portSeparator = authority.firstIndex(of: ":")
            else {
                return .absent
            }
            suffix = authority[authority.index(after: portSeparator)...]
        }

        guard let value = Int(suffix), (1...65535).contains(value) else { return .malformed }
        return .number(value)
    }

    /// Lowercases a host, drops a leading "www." and drops a port. An IPv6
    /// literal keeps its address: only a single colon is read as a port
    /// separator, and a bracketed literal is unwrapped first.
    private static func normalizedHost(_ host: String) -> String {
        var value = host.lowercased()
        if value.hasPrefix("["), let closingBracket = value.firstIndex(of: "]") {
            value = String(value[value.index(after: value.startIndex)..<closingBracket])
        } else if value.filter({ $0 == ":" }).count == 1, let portSeparator = value.firstIndex(of: ":") {
            value = String(value[..<portSeparator])
        }
        if value.hasPrefix("www.") {
            value = String(value.dropFirst(4))
        }
        return value
    }

    func getConfigurationForApp(_ bundleId: String, diagnosticID: String? = nil) -> ModeConfig? {
        for config in configurations.filter({ $0.isEnabled }) {
            let matched = config.allAppConfigs.contains(where: { $0.bundleIdentifier == bundleId })
            if let diagnosticID {
                triggerLogger.notice(
                    "App rule id=\(diagnosticID, privacy: .public) mode=\(config.id.uuidString, privacy: .public) app=\(bundleId, privacy: .public) result=\(matched ? "matched" : "no-matching-app-trigger", privacy: .public)"
                )
            }
            if matched {
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
