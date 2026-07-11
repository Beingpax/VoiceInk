import Foundation

enum ModeTriggerWordDetectionService {
    struct Detection {
        let mode: ModeConfig
        let processedText: String
    }

    static func detect(in text: String, configurations: [ModeConfig]) -> Detection? {
        struct Candidate {
            let mode: ModeConfig
            let triggerWord: String
            let modeIndex: Int
            let wordIndex: Int
        }

        var candidates: [Candidate] = []
        for (modeIndex, config) in configurations.enumerated() {
            for (wordIndex, word) in config.triggerWords.enumerated() {
                let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                candidates.append(
                    Candidate(mode: config, triggerWord: trimmed, modeIndex: modeIndex, wordIndex: wordIndex))
            }
        }

        candidates.sort { lhs, rhs in
            if lhs.triggerWord.count != rhs.triggerWord.count { return lhs.triggerWord.count > rhs.triggerWord.count }
            if lhs.modeIndex != rhs.modeIndex { return lhs.modeIndex < rhs.modeIndex }
            return lhs.wordIndex < rhs.wordIndex
        }

        for candidate in candidates {
            if let processedText = detectAndStrip(from: text, triggerWord: candidate.triggerWord) {
                return Detection(mode: candidate.mode, processedText: processedText)
            }
        }

        return nil
    }

    private static func detectAndStrip(from text: String, triggerWord: String) -> String? {
        if let after = stripTrailing(from: text, triggerWord: triggerWord) {
            return stripLeading(from: after, triggerWord: triggerWord) ?? after
        }
        if let after = stripLeading(from: text, triggerWord: triggerWord) {
            return stripTrailing(from: after, triggerWord: triggerWord) ?? after
        }
        return nil
    }

    private static func stripLeading(from text: String, triggerWord: String) -> String? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmedText.range(of: triggerWord, options: .caseInsensitive),
            range.lowerBound == trimmedText.startIndex
        else { return nil }
        let end = range.upperBound
        if end < trimmedText.endIndex {
            let next = trimmedText[end]
            if next.isLetter || next.isNumber { return nil }
        }
        guard end < trimmedText.endIndex else { return "" }
        var remaining = String(trimmedText[end...])
        remaining = remaining.replacingOccurrences(of: "^[,\\.!\\?;:\\s]+", with: "", options: .regularExpression)
        remaining = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty { remaining = remaining.prefix(1).uppercased() + remaining.dropFirst() }
        return remaining
    }

    private static func stripTrailing(from text: String, triggerWord: String) -> String? {
        var trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let punctuation = CharacterSet(charactersIn: ",.!?;:")
        while let scalar = trimmedText.unicodeScalars.last, punctuation.contains(scalar) { trimmedText.removeLast() }
        guard let range = trimmedText.range(of: triggerWord, options: [.caseInsensitive, .backwards]),
            range.upperBound == trimmedText.endIndex
        else { return nil }
        let start = range.lowerBound
        if start > trimmedText.startIndex {
            let prev = trimmedText[trimmedText.index(before: start)]
            if prev.isLetter || prev.isNumber { return nil }
        }
        var remaining = String(trimmedText[..<start])
        remaining = remaining.replacingOccurrences(of: "[,\\.!\\?;:\\s]+$", with: "", options: .regularExpression)
        remaining = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty { remaining = remaining.prefix(1).uppercased() + remaining.dropFirst() }
        return remaining
    }
}
