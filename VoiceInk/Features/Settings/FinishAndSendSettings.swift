import Foundation

enum FinishAndSendKey: String, Codable, CaseIterable {
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

enum FinishAndSendSettings {
    static let key = "finishAndSendKey"

    static var selectedKey: FinishAndSendKey {
        guard let rawValue = UserDefaults.standard.string(forKey: key) else { return .none }
        return FinishAndSendKey(rawValue: rawValue) ?? .none
    }
}
