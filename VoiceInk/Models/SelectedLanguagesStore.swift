import Foundation

enum SelectedLanguagesStore {
    static let listKey = "SelectedLanguages"
    static let primaryKey = "SelectedLanguage"

    static func read() -> [String] {
        let csv = UserDefaults.standard.string(forKey: listKey)
            ?? UserDefaults.standard.string(forKey: primaryKey)
            ?? "en"
        let parsed = csv
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parsed.isEmpty ? ["en"] : parsed
    }

    static func write(_ languages: [String]) {
        let cleaned = languages
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let final = cleaned.isEmpty ? ["en"] : cleaned

        UserDefaults.standard.set(final.joined(separator: ","), forKey: listKey)
        UserDefaults.standard.set(final.first ?? "en", forKey: primaryKey)
    }

    /// Non-auto codes only — what cloud APIs that take language hints actually want.
    static func languageHints() -> [String] {
        read().filter { $0 != "auto" && !$0.isEmpty }
    }
}
