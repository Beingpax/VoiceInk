import Foundation

enum AppLanguage {
    static let userDefaultsKey = "AppLanguage"
    static let systemRawValue = "system"

    struct Option: Identifiable, Hashable {
        let id: String
        let displayName: String
    }

    static var availableOptions: [Option] {
        let bundle = Bundle.main
        var identifiers = Set(bundle.localizations.filter { $0 != "Base" })

        if let developmentLocalization = bundle.developmentLocalization {
            identifiers.insert(developmentLocalization)
        }

        return identifiers
            .sorted { displayName(for: $0).localizedCaseInsensitiveCompare(displayName(for: $1)) == .orderedAscending }
            .map { Option(id: $0, displayName: displayName(for: $0)) }
    }

    static func locale(for rawValue: String) -> Locale {
        guard rawValue != systemRawValue,
              availableOptions.contains(where: { $0.id == rawValue }) else {
            return .autoupdatingCurrent
        }

        return Locale(identifier: rawValue)
    }

    private static func displayName(for identifier: String) -> String {
        let locale = Locale(identifier: identifier)
        return locale.localizedString(forIdentifier: identifier)
            ?? Locale.current.localizedString(forIdentifier: identifier)
            ?? identifier
    }
}
