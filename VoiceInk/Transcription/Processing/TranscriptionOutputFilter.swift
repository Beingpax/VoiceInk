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
    private static let apostropheLikeCharacters = CharacterSet(charactersIn: "'’‘ʼ＇")
    
    private static let hallucinationPatterns = [
        #"\[.*?\]"#,     // []
        #"\(.*?\)"#,     // ()
        #"\{.*?\}"#      // {}
    ]

    static func filter(_ text: String) -> String {
        var filteredText = text

        // Remove <TAG>...</TAG> blocks
        let tagBlockPattern = #"<([A-Za-z][A-Za-z0-9:_-]*)[^>]*>[\s\S]*?</\1>"#
        if let regex = try? NSRegularExpression(pattern: tagBlockPattern) {
            let range = NSRange(filteredText.startIndex..., in: filteredText)
            filteredText = regex.stringByReplacingMatches(in: filteredText, options: [], range: range, withTemplate: "")
        }

        // Remove bracketed hallucinations
        for pattern in hallucinationPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(filteredText.startIndex..., in: filteredText)
                filteredText = regex.stringByReplacingMatches(in: filteredText, options: [], range: range, withTemplate: "")
            }
        }

        // Remove filler words (if enabled)
        if FillerWordManager.shared.isEnabled {
            for fillerWord in FillerWordManager.shared.fillerWords {
                let pattern = "\\b\(NSRegularExpression.escapedPattern(for: fillerWord))\\b[,.]?"
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let range = NSRange(filteredText.startIndex..., in: filteredText)
                    filteredText = regex.stringByReplacingMatches(in: filteredText, options: [], range: range, withTemplate: "")
                }
            }
        }

        // Smart Silence & Filler Stripper (supercharged repeated and hesitation words)
        if UserDefaults.standard.bool(forKey: "superchargeSmartFillerStripper") {
            // Strip repeated adjacent words (e.g., "the the" -> "the", "I I" -> "I")
            let repeatedWordPattern = "\\b([a-zA-Z]+)\\s+\\1\\b"
            if let regex = try? NSRegularExpression(pattern: repeatedWordPattern, options: .caseInsensitive) {
                let range = NSRange(filteredText.startIndex..., in: filteredText)
                filteredText = regex.stringByReplacingMatches(in: filteredText, options: [], range: range, withTemplate: "$1")
            }
            // Strip hesitation sound artifacts (e.g. "uh-", "um-", etc.)
            let hesitationPattern = "\\b(uh+|um+|ah+|eh+)[-—\\s]+"
            if let regex = try? NSRegularExpression(pattern: hesitationPattern, options: .caseInsensitive) {
                let range = NSRange(filteredText.startIndex..., in: filteredText)
                filteredText = regex.stringByReplacingMatches(in: filteredText, options: [], range: range, withTemplate: "")
            }
        }

        // Clean whitespace
        filteredText = filteredText.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
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

    private static func formatForDeveloper(_ text: String) -> String {
        var formatted = text
        
        let techTerms = [
            "javascript": "JavaScript",
            "typescript": "TypeScript",
            "github": "GitHub",
            "gitlab": "GitLab",
            "vs code": "VS Code",
            "xcode": "Xcode",
            "swiftui": "SwiftUI",
            "uikit": "UIKit",
            "docker": "Docker",
            "kubernetes": "Kubernetes",
            "postgres": "PostgreSQL",
            "postgresql": "PostgreSQL",
            "mongodb": "MongoDB",
            "sqlite": "SQLite"
        ]
        
        for (lower, correct) in techTerms {
            let pattern = "\\b\(lower)\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(formatted.startIndex..., in: formatted)
                formatted = regex.stringByReplacingMatches(in: formatted, options: [], range: range, withTemplate: correct)
            }
        }
        
        let commands = ["npm", "yarn", "pnpm", "git", "docker", "cargo", "pip", "brew", "xcodebuild", "swift"]
        for cmd in commands {
            let pattern = "\\b\(cmd)\\s+([a-z0-9_-]+)"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(formatted.startIndex..., in: formatted)
                formatted = regex.stringByReplacingMatches(in: formatted, options: [], range: range, withTemplate: "`\(cmd) $1`")
            }
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
    
    private static func formatForEmail(_ text: String) -> String {
        var formatted = text
        
        let breaks = [
            "dear ", "hi ", "hello ", "best regards", "sincerely", "thanks,", "thank you"
        ]
        for brk in breaks {
            let pattern = "(?i)\\b(\(brk))"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(formatted.startIndex..., in: formatted)
                formatted = regex.stringByReplacingMatches(in: formatted, options: [], range: range, withTemplate: "\n\n$1")
            }
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
