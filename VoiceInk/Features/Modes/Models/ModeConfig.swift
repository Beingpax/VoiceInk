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

enum ModeRemovalResult {
    case removed
    case blockedDefault
    case notFound
}
