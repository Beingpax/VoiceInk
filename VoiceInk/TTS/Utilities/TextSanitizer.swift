import Foundation

struct TextSanitizer {
    static func cleanImportedText(_ text: String) -> String {
        let newlineNormalized = text.replacingOccurrences(of: "\r", with: "\n")
        let rawLines = newlineNormalized.components(separatedBy: CharacterSet.newlines)

        let boilerplateKeywords: Set<String> = [
            "skip to content",
            "skip content",
            "main menu",
            "menu",
            "search",
            "search website",
            "navigation",
            "site navigation",
            "footer navigation",
            "header navigation",
            "sign in",
            "sign up",
            "log in",
            "log out",
            "account",
            "subscribe",
            "newsletter",
            "share",
            "share this",
            "follow",
            "advertisement",
            "advertising",
            "cookie policy",
            "privacy policy",
            "terms of use",
            "read more",
            "related articles",
            "recent posts",
            "trending",
            "latest",
            "home"
        ]

        var cleaned: [String] = []
        var previousWasBlank = false

        for line in rawLines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                if !previousWasBlank && !cleaned.isEmpty {
                    cleaned.append("")
                }
                previousWasBlank = true
                continue
            }

            let lower = trimmed.lowercased()

            if lower.count <= 35 && boilerplateKeywords.contains(lower) {
                continue
            }

            if lower.contains("skip to") && lower.count <= 50 {
                continue
            }

            if lower.contains("menu") && lower.count <= 60 {
                continue
            }

            if lower.contains("sign") && lower.count <= 40 {
                continue
            }

            if lower.contains("search") && lower.count <= 40 {
                continue
            }

            if lower.contains("cookie") || lower.contains("privacy") {
                continue
            }

            if lower.contains("newsletter") || lower.contains("subscribe") {
                continue
            }

            if lower.contains("advert") {
                continue
            }

            cleaned.append(trimmed)
            previousWasBlank = false
        }

        let joined = cleaned.joined(separator: "\n")
        let condensed = joined.replacingOccurrences(of: "[ \t]{2,}", with: " ", options: .regularExpression)
        return condensed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
