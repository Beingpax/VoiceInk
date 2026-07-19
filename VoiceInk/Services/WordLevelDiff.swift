import Foundation

// Word-level diff between two texts, preserving original casing/punctuation per token —
// unlike WordErrorRateCalculator (which normalizes case/punctuation away because a casing fix
// shouldn't count as a transcription "error"), this is for *showing* a human exactly what an
// AI Enhancement pass changed, where a casing or punctuation fix is precisely the kind of
// change worth seeing (e.g. "pm" -> "PM", "tommorow" -> "tomorrow").
enum WordLevelDiff {

    enum Operation: Equatable {
        case equal(String)
        case substitution(from: String, to: String)
        case deletion(String)
        case insertion(String)
    }

    static func compute(original: String, enhanced: String) -> [Operation] {
        compute(originalWords: tokenize(original), enhancedWords: tokenize(enhanced))
    }

    static func tokenize(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func compute(originalWords: [String], enhancedWords: [String]) -> [Operation] {
        let n = originalWords.count
        let m = enhancedWords.count

        guard n > 0 else { return enhancedWords.map { .insertion($0) } }
        guard m > 0 else { return originalWords.map { .deletion($0) } }

        // dp[i][j] = min edit distance between original[0..<i] and enhanced[0..<j].
        var dp = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { dp[i][0] = i }
        for j in 0...m { dp[0][j] = j }

        for i in 1...n {
            for j in 1...m {
                if originalWords[i - 1] == enhancedWords[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1]
                } else {
                    dp[i][j] = 1 + min(dp[i - 1][j - 1], dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack, same tie-break order as WordErrorRateCalculator (match/sub diagonal,
        // then deletion, then insertion) for a deterministic, familiar alignment.
        var reversedOps: [Operation] = []
        var i = n
        var j = m

        while i > 0 || j > 0 {
            if i > 0, j > 0, originalWords[i - 1] == enhancedWords[j - 1] {
                reversedOps.append(.equal(originalWords[i - 1]))
                i -= 1
                j -= 1
            } else if i > 0, j > 0, dp[i][j] == dp[i - 1][j - 1] + 1 {
                reversedOps.append(.substitution(from: originalWords[i - 1], to: enhancedWords[j - 1]))
                i -= 1
                j -= 1
            } else if i > 0, dp[i][j] == dp[i - 1][j] + 1 {
                reversedOps.append(.deletion(originalWords[i - 1]))
                i -= 1
            } else {
                reversedOps.append(.insertion(enhancedWords[j - 1]))
                j -= 1
            }
        }

        return reversedOps.reversed()
    }
}
