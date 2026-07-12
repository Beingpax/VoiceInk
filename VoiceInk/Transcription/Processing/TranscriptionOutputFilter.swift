import Foundation

struct TranscriptionOutputFilter {
    /// Known ASR artifact/placeholder tokens engines emit for non-speech
    /// segments. ONLY these exact bracketed tokens are stripped; every other
    /// bracketed string (array[i], func(args), "(as I noted)") passes through
    /// untouched.
    private static let artifactTokens = [
        "[BLANK_AUDIO]",
        "[SILENCE]", "(silence)",
        "[NOISE]",
        "[MUSIC]", "(music)",
        "[APPLAUSE]", "(applause)",
        "[LAUGHTER]", "(laughter)",
        "[INAUDIBLE]", "(inaudible)",
        "(unintelligible)",
    ]

    /// One case-insensitive alternation, each alternative anchored to a whole
    /// bracketed token (tolerating internal whitespace, e.g. "[ BLANK_AUDIO ]").
    private static let artifactTokenRegex: NSRegularExpression? = {
        let alternatives = artifactTokens.map { token -> String in
            let open  = NSRegularExpression.escapedPattern(for: String(token.prefix(1)))
            let close = NSRegularExpression.escapedPattern(for: String(token.suffix(1)))
            let inner = NSRegularExpression.escapedPattern(for: String(token.dropFirst().dropLast()))
            return open + #"\s*"# + inner + #"\s*"# + close
        }
        return try? NSRegularExpression(
            pattern: "(?:" + alternatives.joined(separator: "|") + ")",
            options: .caseInsensitive)
    }()

    static func filter(_ text: String) -> String {
        var filteredText = text

        // Remove <TAG>...</TAG> blocks
        let tagBlockPattern = #"<([A-Za-z][A-Za-z0-9:_-]*)[^>]*>[\s\S]*?</\1>"#
        if let regex = try? NSRegularExpression(pattern: tagBlockPattern) {
            let range = NSRange(filteredText.startIndex..., in: filteredText)
            filteredText = regex.stringByReplacingMatches(in: filteredText, options: [], range: range, withTemplate: "")
        }

        // Remove only known ASR artifact tokens (allowlist). Real bracketed
        // content — code identifiers, prose asides — is preserved.
        if let regex = artifactTokenRegex {
            let range = NSRange(filteredText.startIndex..., in: filteredText)
            filteredText = regex.stringByReplacingMatches(
                in: filteredText, options: [], range: range, withTemplate: "")
        }

        // Remove configured filler words. An empty list is naturally a no-op.
        for fillerWord in FillerWordManager.shared.fillerWords {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: fillerWord))\\b[,.]?"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(filteredText.startIndex..., in: filteredText)
                filteredText = regex.stringByReplacingMatches(
                    in: filteredText, options: [], range: range, withTemplate: "")
            }
        }

        // Clean whitespace
        filteredText = filteredText.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        filteredText = filteredText.trimmingCharacters(in: .whitespacesAndNewlines)

        return filteredText
    }
}
