import Foundation
import os

struct TranscriptionOutputFilter {
    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "TranscriptionOutputFilter")
    
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

        // Collapse repetition loops (hallucination defense)
        filteredText = collapseRepetitionLoops(filteredText)

        // Clean whitespace
        filteredText = filteredText.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        filteredText = filteredText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Log results
        if filteredText != text {
            logger.notice("📝 Output filter result: \(filteredText, privacy: .public)")
        } else {
            logger.notice("📝 Output filter result (unchanged): \(filteredText, privacy: .public)")
        }

        return filteredText
    }

    // MARK: - Repetition Loop Collapse

    /// Collapses hallucination loops where whisper repeats the same phrase many times.
    /// Two passes: sentence-level dedup, then n-gram run collapse for unpunctuated output.
    private static func collapseRepetitionLoops(_ text: String) -> String {
        let words = text.split(separator: " ")
        guard words.count >= 10 else { return text }

        var result = text

        // Pass 1: Sentence-level dedup
        result = collapseSentenceRuns(result)

        // Pass 2: N-gram run collapse
        result = collapseNgramRuns(result)

        if result != text {
            logger.notice("🔄 Collapsed repetition loop in transcription output")
        }

        return result
    }

    /// Collapse runs of 3+ consecutive identical sentences.
    private static func collapseSentenceRuns(_ text: String) -> String {
        // Split on sentence-ending punctuation, keeping the delimiter
        let pattern = #"(?<=[.!?])\s+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        let parts = regex.matches(in: text, range: range)

        // If no sentence boundaries found, skip this pass
        guard !parts.isEmpty else { return text }

        // Split into sentences
        var sentences: [String] = []
        var lastEnd = text.startIndex
        for match in parts {
            guard let matchRange = Range(match.range, in: text) else { continue }
            sentences.append(String(text[lastEnd..<matchRange.lowerBound]))
            lastEnd = matchRange.upperBound
        }
        // Append the remainder
        let remainder = String(text[lastEnd...])
        if !remainder.trimmingCharacters(in: .whitespaces).isEmpty {
            sentences.append(remainder)
        }

        guard sentences.count >= 3 else { return text }

        // Detect and collapse runs of 3+ identical sentences
        var collapsed: [String] = []
        var i = 0
        while i < sentences.count {
            let normalized = normalize(sentences[i])
            var runLength = 1
            while i + runLength < sentences.count && normalize(sentences[i + runLength]) == normalized {
                runLength += 1
            }
            collapsed.append(sentences[i])
            if runLength >= 3 {
                logger.notice("🔄 Collapsed \(runLength, privacy: .public) repeated sentences: \"\(sentences[i].prefix(60), privacy: .public)...\"")
            }
            i += runLength
        }

        return collapsed.joined(separator: " ")
    }

    /// Collapse consecutive repeated n-grams (5-12 words) for unpunctuated loops.
    private static func collapseNgramRuns(_ text: String) -> String {
        var words = text.split(separator: " ").map(String.init)
        guard words.count >= 10 else { return text }

        let minN = 5
        let maxN = min(12, words.count / 2)
        guard minN <= maxN else { return text }

        // Try largest n-grams first to prefer collapsing longer patterns
        for n in stride(from: maxN, through: minN, by: -1) {
            let minReps = n >= 8 ? 2 : 3
            var i = 0
            var collapsed = false
            var newWords: [String] = []

            while i <= words.count - n {
                let gram = words[i..<(i + n)].map { $0.lowercased() }
                var reps = 1

                // Count consecutive repetitions of this n-gram
                var j = i + n
                while j + n <= words.count {
                    let candidate = words[j..<(j + n)].map { $0.lowercased() }
                    if candidate == gram {
                        reps += 1
                        j += n
                    } else {
                        break
                    }
                }

                if reps >= minReps {
                    // Keep one copy, skip the rest
                    newWords.append(contentsOf: words[i..<(i + n)])
                    logger.notice("🔄 Collapsed \(reps, privacy: .public)x repeated \(n, privacy: .public)-gram: \"\(words[i..<(i + n)].joined(separator: " ").prefix(60), privacy: .public)...\"")
                    i = j
                    collapsed = true
                } else {
                    newWords.append(words[i])
                    i += 1
                }
            }

            // Append remaining words that couldn't form a full n-gram
            if i < words.count {
                newWords.append(contentsOf: words[i...])
            }

            if collapsed {
                words = newWords
            }
        }

        return words.joined(separator: " ")
    }

    /// Normalize a string for comparison: lowercase, strip punctuation and extra whitespace.
    private static func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: #"[^\w\s]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
