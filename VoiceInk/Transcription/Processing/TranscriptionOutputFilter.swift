import Foundation

enum PunctuationCleanupMode: String, CaseIterable, Codable {
    case keep
    case trailingPunctuation
    case all

    static let userDefaultsKey = "PunctuationCleanupMode"
    static let legacyRemovePunctuationKey = "RemovePunctuation"

    var displayName: String {
        switch self {
        case .keep:
            return "Keep punctuation"
        case .trailingPunctuation:
            return "Remove trailing punctuation"
        case .all:
            return "Remove all punctuation"
        }
    }

    var removesAllPunctuation: Bool {
        self == .all
    }

    static var current: PunctuationCleanupMode {
        mode(
            rawValue: UserDefaults.standard.string(forKey: userDefaultsKey),
            legacyRemovePunctuation: UserDefaults.standard.bool(forKey: legacyRemovePunctuationKey)
        )
    }

    static func mode(rawValue: String?, legacyRemovePunctuation: Bool) -> PunctuationCleanupMode {
        if rawValue == "trailingPeriod" {
            return .trailingPunctuation
        }

        if let rawValue, let mode = PunctuationCleanupMode(rawValue: rawValue) {
            return mode
        }

        return legacyRemovePunctuation ? .all : .keep
    }

    static func persist(_ mode: PunctuationCleanupMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: userDefaultsKey)
        UserDefaults.standard.set(mode.removesAllPunctuation, forKey: legacyRemovePunctuationKey)
    }

    static func persist(rawValue: String) {
        persist(PunctuationCleanupMode(rawValue: rawValue) ?? .keep)
    }
}

struct TranscriptionOutputFilter {
    private static let lowercaseTranscriptionKey = "LowercaseTranscription"
    private static let apostropheLikeCharacters = CharacterSet(charactersIn: "'’‘ʼ＇")
    private static let trailingPunctuationCharacters = CharacterSet.punctuationCharacters.subtracting(apostropheLikeCharacters)
    
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

        // Clean whitespace
        filteredText = filteredText.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        filteredText = filteredText.trimmingCharacters(in: .whitespacesAndNewlines)

        return filteredText
    }

    static func applyUserCleanupPreferences(_ text: String) -> String {
        let punctuationCleanupMode = PunctuationCleanupMode.current
        let shouldLowercase = UserDefaults.standard.bool(forKey: lowercaseTranscriptionKey)

        guard punctuationCleanupMode != .keep || shouldLowercase else {
            return text
        }

        var cleanedText = text
        switch punctuationCleanupMode {
        case .keep:
            break
        case .trailingPunctuation:
            cleanedText = removeTrailingPunctuation(from: cleanedText)
        case .all:
            cleanedText = removePunctuation(from: cleanedText)
        }
        if shouldLowercase {
            cleanedText = cleanedText.lowercased()
        }

        return cleanedText
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

    static func removeTrailingPunctuation(from text: String) -> String {
        guard !text.isEmpty else { return text }

        var endOfContent = text.endIndex
        while endOfContent > text.startIndex {
            let previousIndex = text.index(before: endOfContent)
            if text[previousIndex].isWhitespace {
                endOfContent = previousIndex
            } else {
                break
            }
        }

        guard endOfContent > text.startIndex else { return text }

        var punctuationStart = endOfContent
        while punctuationStart > text.startIndex {
            let previousIndex = text.index(before: punctuationStart)
            if isTrailingPunctuation(text[previousIndex]) {
                punctuationStart = previousIndex
            } else {
                break
            }
        }

        guard punctuationStart < endOfContent else { return text }

        return String(text[..<punctuationStart] + text[endOfContent...])
    }

    private static func isTrailingPunctuation(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { trailingPunctuationCharacters.contains($0) }
    }

    private static func normalizeWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"[^\S\r\n]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n[ \t]+"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
} 
