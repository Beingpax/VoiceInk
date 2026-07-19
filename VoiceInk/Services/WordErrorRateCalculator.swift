import Foundation

// Standard ASR Word Error Rate: WER = (substitutions + deletions + insertions) / reference
// word count, computed via word-level Levenshtein alignment (ADR-0009). Comparison is
// case-insensitive and punctuation-stripped — a deliberate normalization choice (WER has no
// single universal convention), so a transcript differing only in casing or a trailing period
// doesn't count as an error.
enum WordErrorRateCalculator {

    struct Result: Equatable {
        let substitutions: Int
        let deletions: Int
        let insertions: Int
        let referenceWordCount: Int

        var errorCount: Int { substitutions + deletions + insertions }

        // The standard formula divides by referenceWordCount, which is undefined at zero.
        // An empty reference with an empty hypothesis is a perfect (0.0) match; an empty
        // reference with a non-empty hypothesis has nothing to score against but did insert
        // content that shouldn't exist, so it's scored as the worst case (1.0) rather than
        // misread as perfect.
        var wordErrorRate: Double {
            if referenceWordCount == 0 {
                return errorCount == 0 ? 0 : 1
            }
            return Double(errorCount) / Double(referenceWordCount)
        }
    }

    static func evaluate(reference: String, hypothesis: String) -> Result {
        let refWords = normalize(reference)
        let hypWords = normalize(hypothesis)
        return evaluate(referenceWords: refWords, hypothesisWords: hypWords)
    }

    static func normalize(_ text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func evaluate(referenceWords: [String], hypothesisWords: [String]) -> Result {
        let n = referenceWords.count
        let m = hypothesisWords.count

        guard n > 0 else {
            return Result(substitutions: 0, deletions: 0, insertions: m, referenceWordCount: 0)
        }
        guard m > 0 else {
            return Result(substitutions: 0, deletions: n, insertions: 0, referenceWordCount: n)
        }

        // dp[i][j] = min edit distance between reference[0..<i] and hypothesis[0..<j].
        var dp = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { dp[i][0] = i }
        for j in 0...m { dp[0][j] = j }

        for i in 1...n {
            for j in 1...m {
                if referenceWords[i - 1] == hypothesisWords[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1]
                } else {
                    dp[i][j] = 1 + min(dp[i - 1][j - 1], dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack to classify each edit as a substitution, deletion, or insertion.
        // Tie-break order (match/sub diagonal, then deletion, then insertion) matches
        // common WER tooling conventions and is deterministic given the dp table above.
        var substitutions = 0
        var deletions = 0
        var insertions = 0
        var i = n
        var j = m

        while i > 0 || j > 0 {
            if i > 0, j > 0, referenceWords[i - 1] == hypothesisWords[j - 1] {
                i -= 1
                j -= 1
            } else if i > 0, j > 0, dp[i][j] == dp[i - 1][j - 1] + 1 {
                substitutions += 1
                i -= 1
                j -= 1
            } else if i > 0, dp[i][j] == dp[i - 1][j] + 1 {
                deletions += 1
                i -= 1
            } else {
                insertions += 1
                j -= 1
            }
        }

        return Result(substitutions: substitutions, deletions: deletions, insertions: insertions, referenceWordCount: n)
    }
}
