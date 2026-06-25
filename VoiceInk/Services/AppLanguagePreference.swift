import Foundation

enum AppLanguagePreference {
    static let userDefaultsKey = "AppLanguagePreference"
    static let systemValue = "system"

    private static let appleLanguagesKey = "AppleLanguages"
    private static let managesAppleLanguagesKey = "AppLanguagePreferenceManagedAppleLanguages"
    private static let bundledLanguageIdentifiers = ["en", "de", "zh-Hans"]

    struct Option: Identifiable, Hashable {
        let id: String
        let displayName: String
    }

    static var availableOptions: [Option] {
        return [
            Option(id: systemValue, displayName: String(localized: "System"))
        ] + availableLanguageIdentifiers.map { identifier in
            Option(id: identifier, displayName: displayName(for: identifier))
        }
    }

    static var storedRawValue: String {
        let rawValue = UserDefaults.standard.string(forKey: userDefaultsKey) ?? systemValue
        return normalizedRawValue(rawValue)
    }

    static func applyStored() {
        apply(rawValue: storedRawValue)
    }

    static func apply(rawValue: String) {
        let preferenceRawValue = normalizedRawValue(rawValue)

        if preferenceRawValue == systemValue {
            if UserDefaults.standard.bool(forKey: managesAppleLanguagesKey) {
                UserDefaults.standard.removeObject(forKey: appleLanguagesKey)
            }
            UserDefaults.standard.removeObject(forKey: managesAppleLanguagesKey)
        } else {
            UserDefaults.standard.set([preferenceRawValue], forKey: appleLanguagesKey)
            UserDefaults.standard.set(true, forKey: managesAppleLanguagesKey)
        }
    }

    static func normalizedRawValue(_ rawValue: String) -> String {
        guard rawValue != systemValue else { return systemValue }
        return availableLanguageIdentifiers.contains(rawValue) ? rawValue : systemValue
    }

    private static var availableLanguageIdentifiers: [String] {
        let localizedBundleIdentifiers = Bundle.main.localizations.filter { identifier in
            identifier != "Base" && !identifier.isEmpty
        }

        let discoveredIdentifiers = Set(bundledLanguageIdentifiers + localizedBundleIdentifiers)
        let bundledIdentifiers = bundledLanguageIdentifiers.filter { discoveredIdentifiers.contains($0) }
        let additionalIdentifiers = discoveredIdentifiers
            .subtracting(bundledLanguageIdentifiers)
            .sorted { displayName(for: $0) < displayName(for: $1) }

        return bundledIdentifiers + additionalIdentifiers
    }

    private static func displayName(for identifier: String) -> String {
        Locale(identifier: identifier).localizedString(forIdentifier: identifier) ?? identifier
    }
}
