import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    static let userDefaultsKey = "AppAppearance"

    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .system:
            "System"
        case .light:
            "Light"
        case .dark:
            "Dark"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    static func preferredColorScheme(for rawValue: String) -> ColorScheme? {
        AppAppearance(rawValue: rawValue)?.preferredColorScheme
    }
}
