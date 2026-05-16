import Foundation

enum PunctuationMode: String, Codable, CaseIterable, Identifiable {
    case keep
    case removeTrailing
    case removeAll

    static let defaultsKey = "PunctuationMode"
    static let legacyRemovePunctuationKey = "RemovePunctuation"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .keep:
            return "Keep"
        case .removeTrailing:
            return "Remove ending"
        case .removeAll:
            return "Remove all"
        }
    }

    var helpText: String {
        switch self {
        case .keep:
            return "Keep punctuation from recording transcription output."
        case .removeTrailing:
            return "Remove punctuation only from the end of recording transcription output."
        case .removeAll:
            return "Remove all punctuation marks from recording transcription output."
        }
    }

    init(removePunctuation: Bool) {
        self = removePunctuation ? .removeAll : .keep
    }

    static func stored(in defaults: UserDefaults = .standard) -> PunctuationMode {
        if let rawValue = defaults.string(forKey: defaultsKey),
           let mode = PunctuationMode(rawValue: rawValue) {
            return mode
        }

        return PunctuationMode(
            removePunctuation: defaults.bool(forKey: legacyRemovePunctuationKey)
        )
    }

    static func persist(_ mode: PunctuationMode, in defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: defaultsKey)
    }

    static func migrateLegacyDefaultIfNeeded(in defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: defaultsKey) == nil else { return }
        persist(stored(in: defaults), in: defaults)
    }
}

extension UserDefaults {
    var punctuationMode: PunctuationMode {
        get {
            PunctuationMode.stored(in: self)
        }
        set {
            PunctuationMode.persist(newValue, in: self)
        }
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

        // Clean whitespace
        filteredText = filteredText.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        filteredText = filteredText.trimmingCharacters(in: .whitespacesAndNewlines)

        return filteredText
    }

    static func applyUserCleanupPreferences(_ text: String) -> String {
        applyCleanupPreferences(text, punctuationMode: .keep)
    }

    static func applyRecordingCleanupPreferences(_ text: String) -> String {
        applyCleanupPreferences(text, punctuationMode: UserDefaults.standard.punctuationMode)
    }

    private static func applyCleanupPreferences(_ text: String, punctuationMode: PunctuationMode) -> String {
        let shouldLowercase = UserDefaults.standard.bool(forKey: lowercaseTranscriptionKey)

        guard punctuationMode != .keep || shouldLowercase else {
            return text
        }

        var cleanedText = text
        switch punctuationMode {
        case .keep:
            break
        case .removeTrailing:
            cleanedText = removeTrailingPunctuation(from: cleanedText)
        case .removeAll:
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

        let punctuationCharacters = CharacterSet.punctuationCharacters.union(apostropheLikeCharacters)
        var cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        while let lastScalar = cleanedText.unicodeScalars.last,
              punctuationCharacters.contains(lastScalar) {
            cleanedText.removeLast()
            cleanedText = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return cleanedText
    }

    private static func normalizeWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"[^\S\r\n]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n[ \t]+"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
} 
