import Foundation
#if canImport(AppKit)
import AppKit
#endif

enum PunctuationCleanupMode: String, Codable, CaseIterable, Identifiable {
    case keep = "keep"
    case removeAll = "removeAll"
    case removeTrailingPeriod = "removeTrailingPeriod"

    static let userDefaultsKey = "PunctuationCleanupMode"
    static let legacyRemovePunctuationKey = "RemovePunctuation"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .keep:
            return "Keep"
        case .removeAll:
            return "Remove all"
        case .removeTrailingPeriod:
            return "Remove trailing period"
        }
    }

    static func current(in defaults: UserDefaults = .standard) -> PunctuationCleanupMode {
        if let rawValue = defaults.string(forKey: userDefaultsKey),
           let mode = PunctuationCleanupMode(rawValue: rawValue) {
            return mode
        }

        return defaults.bool(forKey: legacyRemovePunctuationKey) ? .removeAll : .keep
    }

    static func setCurrent(_ mode: PunctuationCleanupMode, in defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: userDefaultsKey)
        defaults.set(mode == .removeAll, forKey: legacyRemovePunctuationKey)
    }

    static func migrateLegacyUserDefaultIfNeeded(in defaults: UserDefaults = .standard) {
        if let rawValue = defaults.string(forKey: userDefaultsKey),
           PunctuationCleanupMode(rawValue: rawValue) != nil {
            return
        }

        setCurrent(defaults.bool(forKey: legacyRemovePunctuationKey) ? .removeAll : .keep, in: defaults)
    }
}

struct TranscriptionOutputFilter {
    private static let lowercaseTranscriptionKey = "LowercaseTranscription"
    private static let apostropheLikeCharacters = CharacterSet(charactersIn: "'''ʼ＇")
    
    // MARK: - Pre-compiled Regexes (avoids recompilation on every transcription)
    
    private static let tagBlockRegex = try! NSRegularExpression(pattern: #"<([A-Za-z][A-Za-z0-9:_-]*)[^>]*>[\s\S]*?</\1>"#)
    private static let hallucinationRegexes: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: #"\[.*?\]"#),
        try! NSRegularExpression(pattern: #"\(.*?\)"#),
        try! NSRegularExpression(pattern: #"\{.*?\}"#)
    ]
    private static let repeatedWordRegex = try! NSRegularExpression(pattern: "\\b([a-zA-Z]+)\\s+\\1\\b", options: .caseInsensitive)
    private static let hesitationRegex = try! NSRegularExpression(pattern: "\\b(uh+|um+|ah+|eh+)[-—\\s]+", options: .caseInsensitive)
    private static let multiSpaceRegex = try! NSRegularExpression(pattern: #"\s{2,}"#)

    static func filter(_ text: String) -> String {
        var filteredText = text

        // Remove <TAG>...</TAG> blocks
        var range = NSRange(filteredText.startIndex..., in: filteredText)
        filteredText = tagBlockRegex.stringByReplacingMatches(in: filteredText, options: [], range: range, withTemplate: "")

        // Remove bracketed hallucinations
        for regex in hallucinationRegexes {
            range = NSRange(filteredText.startIndex..., in: filteredText)
            filteredText = regex.stringByReplacingMatches(in: filteredText, options: [], range: range, withTemplate: "")
        }

        // Remove filler words (if enabled) — uses pre-compiled regexes from FillerWordManager
        if FillerWordManager.shared.isEnabled {
            for regex in FillerWordManager.shared.compiledFillerRegexes {
                range = NSRange(filteredText.startIndex..., in: filteredText)
                filteredText = regex.stringByReplacingMatches(in: filteredText, options: [], range: range, withTemplate: "")
            }
        }

        // Smart Silence & Filler Stripper
        if UserDefaults.standard.bool(forKey: "superchargeSmartFillerStripper") {
            range = NSRange(filteredText.startIndex..., in: filteredText)
            filteredText = repeatedWordRegex.stringByReplacingMatches(in: filteredText, options: [], range: range, withTemplate: "$1")
            range = NSRange(filteredText.startIndex..., in: filteredText)
            filteredText = hesitationRegex.stringByReplacingMatches(in: filteredText, options: [], range: range, withTemplate: "")
        }

        // Clean whitespace
        range = NSRange(filteredText.startIndex..., in: filteredText)
        filteredText = multiSpaceRegex.stringByReplacingMatches(in: filteredText, options: [], range: range, withTemplate: " ")
        filteredText = filteredText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Context-Aware Auto-Formatting
        if UserDefaults.standard.bool(forKey: "superchargeContextAwareFormatting") {
            filteredText = applyContextAwareFormatting(filteredText)
        }

        return filteredText
    }

    #if canImport(AppKit)
    static var frontmostAppBundleIdentifier: String? {
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
    #else
    static var frontmostAppBundleIdentifier: String? {
        return nil
    }
    #endif

    static func applyContextAwareFormatting(_ text: String) -> String {
        guard let bundleId = frontmostAppBundleIdentifier?.lowercased() else { return text }
        
        // Developer apps
        if bundleId.contains("vscode") || bundleId.contains("xcode") || bundleId.contains("terminal") || bundleId.contains("iterm") {
            return formatForDeveloper(text)
        }
        
        // Chat apps
        if bundleId.contains("slack") || bundleId.contains("discord") || bundleId.contains("teams") {
            return formatForChat(text)
        }
        
        // Email/Writing apps
        if bundleId.contains("mail") || bundleId.contains("outlook") || bundleId.contains("pages") {
            return formatForEmail(text)
        }
        
        return text
    }

    // Pre-compiled developer formatting regexes
    private static let techTermRegexes: [(NSRegularExpression, String)] = {
        let terms = [
            "javascript": "JavaScript", "typescript": "TypeScript",
            "github": "GitHub", "gitlab": "GitLab", "vs code": "VS Code",
            "xcode": "Xcode", "swiftui": "SwiftUI", "uikit": "UIKit",
            "docker": "Docker", "kubernetes": "Kubernetes",
            "postgres": "PostgreSQL", "postgresql": "PostgreSQL",
            "mongodb": "MongoDB", "sqlite": "SQLite"
        ]
        return terms.compactMap { (lower, correct) in
            guard let regex = try? NSRegularExpression(pattern: "\\b\(lower)\\b", options: .caseInsensitive) else { return nil }
            return (regex, correct)
        }
    }()

    private static let commandRegexes: [(NSRegularExpression, String)] = {
        let commands = ["npm", "yarn", "pnpm", "git", "docker", "cargo", "pip", "brew", "xcodebuild", "swift"]
        return commands.compactMap { cmd in
            guard let regex = try? NSRegularExpression(pattern: "\\b\(cmd)\\s+([a-z0-9_-]+)", options: []) else { return nil }
            return (regex, "`\(cmd) $1`")
        }
    }()

    private static func formatForDeveloper(_ text: String) -> String {
        var formatted = text

        for (regex, replacement) in techTermRegexes {
            let range = NSRange(formatted.startIndex..., in: formatted)
            formatted = regex.stringByReplacingMatches(in: formatted, options: [], range: range, withTemplate: replacement)
        }

        for (regex, replacement) in commandRegexes {
            let range = NSRange(formatted.startIndex..., in: formatted)
            formatted = regex.stringByReplacingMatches(in: formatted, options: [], range: range, withTemplate: replacement)
        }

        return formatted
    }
    
    private static func formatForChat(_ text: String) -> String {
        var formatted = text
        
        if formatted.count < 80 && formatted.hasSuffix(".") {
            formatted.removeLast()
        }
        
        let emojis = [
            ":)": "🙂",
            ":-)": "🙂",
            ":D": "😀",
            ":(": "🙁",
            "<3": "❤️"
        ]
        for (emote, emoji) in emojis {
            formatted = formatted.replacingOccurrences(of: emote, with: emoji)
        }
        
        return formatted
    }
    
    // Pre-compiled email formatting regexes
    private static let emailBreakRegexes: [NSRegularExpression] = {
        let breaks = ["dear ", "hi ", "hello ", "best regards", "sincerely", "thanks,", "thank you"]
        return breaks.compactMap { brk in
            try? NSRegularExpression(pattern: "(?i)\\b(\(brk))", options: [])
        }
    }()

    private static func formatForEmail(_ text: String) -> String {
        var formatted = text

        for regex in emailBreakRegexes {
            let range = NSRange(formatted.startIndex..., in: formatted)
            formatted = regex.stringByReplacingMatches(in: formatted, options: [], range: range, withTemplate: "\n\n$1")
        }

        formatted = formatted.trimmingCharacters(in: .whitespacesAndNewlines)
        return formatted
    }

    static func applyUserCleanupPreferences(_ text: String) -> String {
        let punctuationMode = PunctuationCleanupMode.current()
        let shouldLowercase = UserDefaults.standard.bool(forKey: lowercaseTranscriptionKey)

        return applyCleanupPreferences(text, punctuationMode: punctuationMode, shouldLowercase: shouldLowercase)
    }

    static func applyCleanupPreferences(_ text: String, punctuationMode: PunctuationCleanupMode, shouldLowercase: Bool) -> String {
        guard punctuationMode != .keep || shouldLowercase else {
            return text
        }

        var cleanedText = text
        switch punctuationMode {
        case .keep:
            break
        case .removeAll:
            cleanedText = removePunctuation(from: cleanedText)
        case .removeTrailingPeriod:
            cleanedText = removeTrailingPeriod(from: cleanedText)
        }

        if shouldLowercase {
            cleanedText = cleanedText.lowercased()
        }

        return cleanedText
    }

    static func removeTrailingPeriod(from text: String) -> String {
        guard !text.isEmpty else { return text }

        let trailingWhitespace = text.reversed().prefix { $0.isWhitespace }
        let trimmedEndIndex = text.index(text.endIndex, offsetBy: -trailingWhitespace.count)
        guard trimmedEndIndex > text.startIndex else { return text }

        let lastCharIndex = text.index(before: trimmedEndIndex)
        guard text[lastCharIndex] == "." else { return text }

        if lastCharIndex > text.startIndex {
            let previousCharIndex = text.index(before: lastCharIndex)
            guard text[previousCharIndex] != "." else { return text }
        }

        var result = text
        result.remove(at: lastCharIndex)
        return result
    }

    static func removePunctuation(from text: String) -> String {
        guard !text.isEmpty else { return text }

        let punctuationSeparators = CharacterSet.punctuationCharacters.subtracting(apostropheLikeCharacters)
        let cleanedScalars = text.unicodeScalars.map { scalar -> String in
            if apostropheLikeCharacters.contains(scalar) {
                return ""
            }

            if punctuationSeparators.contains(scalar) {
                return " "
            }

            return String(scalar)
        }

        return normalizeWhitespace(cleanedScalars.joined())
    }

    private static func normalizeWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"[^\S\r\n]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n[ \t]+"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
} 
