import Foundation

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

        // Remove configured filler words. An empty list is naturally a no-op.
        for fillerWord in FillerWordManager.shared.fillerWords {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: fillerWord))\\b[,.]?"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(filteredText.startIndex..., in: filteredText)
                filteredText = regex.stringByReplacingMatches(in: filteredText, options: [], range: range, withTemplate: "")
            }
        }

        // Clean whitespace
        filteredText = filteredText.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        filteredText = filteredText.trimmingCharacters(in: .whitespacesAndNewlines)

        return filteredText
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
