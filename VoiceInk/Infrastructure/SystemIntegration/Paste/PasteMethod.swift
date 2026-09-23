import Foundation

enum PasteMethod: String, CaseIterable, Identifiable {
    case standard = "default"
    case appleScript = "appleScript"
    case directTyping = "directTyping"

    static let userDefaultsKey = "pasteMethod"
    static let legacyAppleScriptPasteKey = "useAppleScriptPaste"
    static let legacyCGEventRawValue = "cgEvent"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard:
            return String(localized: "Default")
        case .appleScript:
            return String(localized: "AppleScript")
        case .directTyping:
            return String(localized: "Direct Typing")
        }
    }

    static func resolve(_ rawValue: String) -> PasteMethod? {
        if rawValue == legacyCGEventRawValue {
            return .standard
        }
        return PasteMethod(rawValue: rawValue)
    }

    static func current(in defaults: UserDefaults = .standard) -> PasteMethod {
        if let rawValue = defaults.string(forKey: userDefaultsKey),
            let method = resolve(rawValue)
        {
            return method
        }

        return defaults.bool(forKey: legacyAppleScriptPasteKey) ? .appleScript : .standard
    }

    static func setCurrent(_ method: PasteMethod, in defaults: UserDefaults = .standard) {
        defaults.set(method.rawValue, forKey: userDefaultsKey)
        defaults.set(method == .appleScript, forKey: legacyAppleScriptPasteKey)
    }

    static func migrateLegacyUserDefaultIfNeeded(in defaults: UserDefaults = .standard) {
        if let rawValue = defaults.string(forKey: userDefaultsKey) {
            if rawValue == legacyCGEventRawValue {
                setCurrent(.standard, in: defaults)
                return
            }
            if PasteMethod(rawValue: rawValue) != nil {
                return
            }
        }

        setCurrent(defaults.bool(forKey: legacyAppleScriptPasteKey) ? .appleScript : .standard, in: defaults)
    }
}
