import Foundation

enum ShortcutStore {
    static let shortcutDidChange = Notification.Name("ShortcutStoreShortcutDidChange")

    static func rawShortcut(for action: ShortcutAction) -> Shortcut? {
        shortcutData(for: action)
            .flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
    }

    static func shortcut(for action: ShortcutAction) -> Shortcut? {
        guard action.isStored else {
            return nil
        }

        guard !isShortcutCleared(for: action) else {
            return nil
        }

        return rawShortcut(for: action)
    }

    static func setShortcut(_ shortcut: Shortcut?, for action: ShortcutAction) {
        guard action.isStored else {
            return
        }

        if let shortcut, ShortcutValidator.validationError(for: shortcut, action: action) != nil {
            return
        }

        if let shortcut,
            let data = try? JSONEncoder().encode(shortcut)
        {
            UserDefaults.standard.set(data, forKey: action.userDefaultsKey)
            UserDefaults.standard.removeObject(forKey: clearedUserDefaultsKey(for: action))
            ShortcutMigration.removeLegacyCustomRecordingShortcut(for: action)
            ShortcutMigration.removeLegacyKeyboardShortcut(for: action)
        } else {
            UserDefaults.standard.removeObject(forKey: action.userDefaultsKey)
            UserDefaults.standard.set(true, forKey: clearedUserDefaultsKey(for: action))
            ShortcutMigration.removeLegacyCustomRecordingShortcut(for: action)
            ShortcutMigration.removeLegacyKeyboardShortcut(for: action)
        }

        NotificationCenter.default.post(
            name: shortcutDidChange,
            object: action
        )
    }

    static func seedShortcut(
        _ shortcut: Shortcut,
        for action: ShortcutAction,
        replacingCleared: Bool = false
    ) {
        guard action.isStored,
            rawShortcut(for: action) == nil,
            replacingCleared || !isShortcutCleared(for: action)
        else {
            return
        }

        setShortcut(shortcut, for: action)
    }

    static func removeShortcutStorage(for action: ShortcutAction) {
        guard action.isStored else {
            return
        }

        UserDefaults.standard.removeObject(forKey: action.userDefaultsKey)
        UserDefaults.standard.removeObject(forKey: clearedUserDefaultsKey(for: action))
        ShortcutMigration.removeLegacyCustomRecordingShortcut(for: action)
        ShortcutMigration.removeLegacyKeyboardShortcut(for: action)
        NotificationCenter.default.post(
            name: shortcutDidChange,
            object: action
        )
    }

    static func shortcuts(for actions: [ShortcutAction]) -> [ShortcutAction: Shortcut] {
        actions.reduce(into: [:]) { result, action in
            if let shortcut = shortcut(for: action) {
                result[action] = shortcut
            }
        }
    }

    private static func shortcutData(for action: ShortcutAction) -> Data? {
        UserDefaults.standard.data(forKey: action.userDefaultsKey)
    }

    static func isShortcutCleared(for action: ShortcutAction) -> Bool {
        UserDefaults.standard.bool(forKey: clearedUserDefaultsKey(for: action))
    }

    private static func clearedUserDefaultsKey(for action: ShortcutAction) -> String {
        "\(action.userDefaultsKey)_cleared"
    }
}
