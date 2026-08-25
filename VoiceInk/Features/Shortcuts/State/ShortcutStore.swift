import Foundation

enum ShortcutStore {
    static let shortcutDidChange = Notification.Name("ShortcutStoreShortcutDidChange")

    static func rawShortcut(for action: ShortcutAction) -> Shortcut? {
        guard let data = shortcutData(for: action) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(Shortcut.self, from: data)
        } catch {
            ShortcutDiagnostics.error(
                "shortcut-store read action=\(action.storageName) result=decode-failed bytes=\(data.count) error=\(error.localizedDescription)"
            )
            return nil
        }
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

        if let shortcut, let validationError = ShortcutValidator.validationError(for: shortcut, action: action) {
            ShortcutDiagnostics.error(
                "shortcut-store write action=\(action.storageName) result=validation-rejected reason=\(String(describing: validationError)) shortcut=\(shortcut.diagnosticDescription)"
            )
            return
        }

        if let shortcut,
            let data = try? JSONEncoder().encode(shortcut)
        {
            UserDefaults.standard.set(data, forKey: action.userDefaultsKey)
            UserDefaults.standard.removeObject(forKey: clearedUserDefaultsKey(for: action))
            ShortcutMigration.removeLegacyCustomRecordingShortcut(for: action)
            ShortcutMigration.removeLegacyKeyboardShortcut(for: action)
            ShortcutDiagnostics.notice(
                "shortcut-store write action=\(action.storageName) result=saved shortcut=\(shortcut.diagnosticDescription)"
            )
        } else {
            UserDefaults.standard.removeObject(forKey: action.userDefaultsKey)
            UserDefaults.standard.set(true, forKey: clearedUserDefaultsKey(for: action))
            ShortcutMigration.removeLegacyCustomRecordingShortcut(for: action)
            ShortcutMigration.removeLegacyKeyboardShortcut(for: action)
            ShortcutDiagnostics.notice("shortcut-store write action=\(action.storageName) result=cleared")
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
            ShortcutDiagnostics.notice(
                "shortcut-store seed action=\(action.storageName) result=skipped replacingCleared=\(replacingCleared) hasRaw=\(rawShortcut(for: action) != nil) isCleared=\(isShortcutCleared(for: action))"
            )
            return
        }

        ShortcutDiagnostics.notice(
            "shortcut-store seed action=\(action.storageName) result=attempt shortcut=\(shortcut.diagnosticDescription)"
        )
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
        ShortcutDiagnostics.notice("shortcut-store remove action=\(action.storageName) result=storage-removed")
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
