import AppKit
import Carbon.HIToolbox
import Foundation

struct LegacyKeyboardShortcut: Codable {
    let carbonKeyCode: Int
    let carbonModifiers: Int
}

struct ShortcutBackup: Codable {
    let shortcut: Shortcut

    init(_ shortcut: Shortcut) {
        self.shortcut = shortcut
    }

    init(from decoder: Decoder) throws {
        if let shortcut = try? Shortcut(from: decoder) {
            self.shortcut = shortcut
            return
        }

        let legacyShortcut = try LegacyKeyboardShortcut(from: decoder)
        self.shortcut = Shortcut.fromLegacyShortcut(legacyShortcut)
    }

    func encode(to encoder: Encoder) throws {
        try shortcut.encode(to: encoder)
    }
}

enum ShortcutMigration {
    static func migrateLegacyShortcutsIfNeeded() {
        discardLegacyCustomRecordingShortcutsIfNeeded()
        migrateLegacyKeyboardShortcutsIfNeeded()
    }

    static func migrateLegacyKeyboardShortcutsIfNeeded() {
        let migrationKey = "Shortcut_LegacyKeyboardShortcutsMigrated"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else {
            return
        }

        for action in ShortcutAction.legacyKeyboardShortcutActions {
            migrateLegacyKeyboardShortcut(for: action)
        }

        for config in ModeManager.shared.configurations {
            migrateLegacyKeyboardShortcut(for: .mode(config.id))
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    static func migrateShortcutSelection(
        action: ShortcutAction,
        allowsNone: Bool
    ) -> RecordingShortcutManager.ShortcutSelection {
        let userDefaultsKey = recordingShortcutKey(for: action)
        let legacyKey = legacyRecordingShortcutKey(for: action)

        if let storedValue = nonEmptyString(forKey: userDefaultsKey) {
            return shortcutSelection(
                from: storedValue,
                savingTo: userDefaultsKey,
                removing: legacyKey,
                action: action,
                allowsNone: allowsNone
            )
        }

        if let legacyValue = nonEmptyString(forKey: legacyKey) {
            return shortcutSelection(
                from: legacyValue,
                savingTo: userDefaultsKey,
                removing: legacyKey,
                action: action,
                allowsNone: allowsNone
            )
        }

        if !allowsNone {
            return .custom
        }

        return .none
    }

    static func migrateShortcutMode(
        for action: ShortcutAction
    ) -> RecordingShortcutManager.Mode {
        let userDefaultsKey = recordingShortcutModeKey(for: action)
        let legacyKey = legacyRecordingShortcutModeKey(for: action)

        if let storedValue = nonEmptyString(forKey: userDefaultsKey),
           let mode = RecordingShortcutManager.Mode(rawValue: storedValue) {
            UserDefaults.standard.removeObject(forKey: legacyKey)
            return mode
        }

        if let legacyValue = nonEmptyString(forKey: legacyKey),
           let mode = RecordingShortcutManager.Mode(rawValue: legacyValue) {
            UserDefaults.standard.set(mode.rawValue, forKey: userDefaultsKey)
            UserDefaults.standard.removeObject(forKey: legacyKey)
            return mode
        }

        return .hybrid
    }

    private static func shortcutSelection(
        from storedValue: String,
        savingTo userDefaultsKey: String,
        removing legacyKey: String?,
        action: ShortcutAction,
        allowsNone: Bool
    ) -> RecordingShortcutManager.ShortcutSelection {
        if storedValue == RecordingShortcutManager.ShortcutSelection.custom.rawValue {
            saveShortcutSelection(.custom, forKey: userDefaultsKey, removing: legacyKey)
            return .custom
        }

        if storedValue == RecordingShortcutManager.ShortcutSelection.none.rawValue {
            let selection: RecordingShortcutManager.ShortcutSelection = allowsNone ? .none : .custom
            saveShortcutSelection(selection, forKey: userDefaultsKey, removing: legacyKey)
            return selection
        }

        if let shortcut = legacyPresetShortcut(for: storedValue),
           !isRecordingShortcutAction(action) {
            ShortcutStore.setShortcut(shortcut, for: action)
            saveShortcutSelection(.custom, forKey: userDefaultsKey, removing: legacyKey)
            return .custom
        }

        let selection: RecordingShortcutManager.ShortcutSelection = allowsNone ? .none : .custom
        saveShortcutSelection(selection, forKey: userDefaultsKey, removing: legacyKey)
        return selection
    }

    private static func saveShortcutSelection(
        _ selection: RecordingShortcutManager.ShortcutSelection,
        forKey userDefaultsKey: String,
        removing legacyKey: String?
    ) {
        UserDefaults.standard.set(selection.rawValue, forKey: userDefaultsKey)

        if let legacyKey {
            UserDefaults.standard.removeObject(forKey: legacyKey)
        }
    }

    static func removeLegacyCustomRecordingShortcut(for action: ShortcutAction) {
        UserDefaults.standard.removeObject(forKey: legacyCustomRecordingShortcutKey(for: action))
    }

    static func removeLegacyKeyboardShortcut(for action: ShortcutAction) {
        for legacyName in legacyKeyboardShortcutsNames(for: action) {
            UserDefaults.standard.removeObject(forKey: "KeyboardShortcuts_\(legacyName)")
        }
    }

    static func migrateLegacyKeyboardShortcut(for action: ShortcutAction) {
        defer {
            removeLegacyKeyboardShortcut(for: action)
        }

        guard !isRecordingShortcutAction(action) else {
            return
        }

        guard
            ShortcutStore.rawShortcut(for: action) == nil,
            !ShortcutStore.isShortcutCleared(for: action),
            let shortcut = legacyKeyboardShortcut(for: action)
        else {
            return
        }

        ShortcutStore.setShortcut(shortcut, for: action)
    }

    private static func discardLegacyCustomRecordingShortcutsIfNeeded() {
        let migrationKey = "Shortcut_LegacyCustomRecordingShortcutsMigrated"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else {
            return
        }

        for action in [ShortcutAction.primaryRecording, .secondaryRecording] {
            removeLegacyCustomRecordingShortcut(for: action)
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    private static func legacyPresetShortcut(for rawValue: String) -> Shortcut? {
        switch rawValue {
        case "rightOption":
            return .modifierOnly(keyCode: UInt16(kVK_RightOption), modifierFlags: [.option])
        case "leftOption":
            return .modifierOnly(keyCode: UInt16(kVK_Option), modifierFlags: [.option])
        case "leftControl":
            return .modifierOnly(keyCode: UInt16(kVK_Control), modifierFlags: [.control])
        case "rightControl":
            return .modifierOnly(keyCode: UInt16(kVK_RightControl), modifierFlags: [.control])
        case "fn":
            return .modifierOnly(keyCode: UInt16(kVK_Function), modifierFlags: [.function])
        case "rightCommand":
            return .modifierOnly(keyCode: UInt16(kVK_RightCommand), modifierFlags: [.command])
        case "rightShift":
            return .modifierOnly(keyCode: UInt16(kVK_RightShift), modifierFlags: [.shift])
        default:
            return nil
        }
    }

    private static func isRecordingShortcutAction(_ action: ShortcutAction) -> Bool {
        switch action {
        case .primaryRecording, .secondaryRecording:
            return true
        default:
            return false
        }
    }

    private static func legacyCustomRecordingShortcutKey(for action: ShortcutAction) -> String {
        switch action {
        case .primaryRecording:
            return "CustomRecordingShortcut_primary"
        case .secondaryRecording:
            return "CustomRecordingShortcut_secondary"
        default:
            return "CustomRecordingShortcut_\(action.storageName)"
        }
    }

    private static func legacyKeyboardShortcut(for action: ShortcutAction) -> Shortcut? {
        guard
            let legacyName = legacyKeyboardShortcutsNames(for: action).first(where: {
                UserDefaults.standard.string(forKey: "KeyboardShortcuts_\($0)") != nil
            }),
            let data = UserDefaults.standard.string(forKey: "KeyboardShortcuts_\(legacyName)")?.data(using: .utf8),
            let legacyShortcut = try? JSONDecoder().decode(LegacyKeyboardShortcut.self, from: data)
        else {
            return nil
        }

        return Shortcut.fromLegacyShortcut(legacyShortcut)
    }

    private static func legacyKeyboardShortcutsNames(for action: ShortcutAction) -> [String] {
        switch action {
        case .primaryRecording:
            return ["toggleMiniRecorder"]
        case .secondaryRecording:
            return ["toggleMiniRecorder2"]
        case .pasteLastTranscription:
            return ["pasteLastTranscription"]
        case .pasteLastEnhancement:
            return ["pasteLastEnhancement"]
        case .retryLastTranscription:
            return ["retryLastTranscription"]
        case .cancelRecorder:
            return ["cancelRecorder"]
        case .openHistoryWindow:
            return ["openHistoryWindow"]
        case .quickAddToDictionary:
            return ["quickAddToDictionary"]
        case .mode(let id):
            return ["mode_\(id.uuidString)", "powerMode_\(id.uuidString)"]
        case .recorderPanelEscape, .recorderPanelMode:
            return []
        }
    }

    private static func recordingShortcutKey(for action: ShortcutAction) -> String {
        switch action {
        case .primaryRecording:
            return "primaryRecordingShortcut"
        case .secondaryRecording:
            return "secondaryRecordingShortcut"
        default:
            return action.userDefaultsKey
        }
    }

    private static func legacyRecordingShortcutKey(for action: ShortcutAction) -> String {
        switch action {
        case .primaryRecording:
            return "selectedHotkey1"
        case .secondaryRecording:
            return "selectedHotkey2"
        default:
            return action.userDefaultsKey
        }
    }

    private static func recordingShortcutModeKey(for action: ShortcutAction) -> String {
        switch action {
        case .primaryRecording:
            return "primaryRecordingShortcutMode"
        case .secondaryRecording:
            return "secondaryRecordingShortcutMode"
        default:
            return action.userDefaultsKey
        }
    }

    private static func legacyRecordingShortcutModeKey(for action: ShortcutAction) -> String {
        switch action {
        case .primaryRecording:
            return "hotkeyMode1"
        case .secondaryRecording:
            return "hotkeyMode2"
        default:
            return action.userDefaultsKey
        }
    }

    private static func nonEmptyString(forKey key: String) -> String? {
        guard
            let value = UserDefaults.standard.string(forKey: key),
            !value.isEmpty
        else {
            return nil
        }

        return value
    }
}
