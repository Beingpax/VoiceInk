import Foundation

struct VocabularyCandidate: Hashable {
 let rawPhrase: String
 let correctedPhrase: String
}

struct VocabularyDiffEngine {

 static func extractCandidates(raw: String, enhanced: String, commonWords: Set<String>) -> [VocabularyCandidate] {
  let rawTokens = tokenize(raw)
  let enhancedTokens = tokenize(enhanced)

  guard !rawTokens.isEmpty, !enhancedTokens.isEmpty else { return [] }

  let lcsIndices = longestCommonSubsequence(rawTokens.map { $0.normalized }, enhancedTokens.map { $0.normalized })

  let corrections = extractCorrections(rawTokens: rawTokens, enhancedTokens: enhancedTokens, lcs: lcsIndices)

  return corrections.compactMap { correction -> VocabularyCandidate? in
   let rawPhrase = correction.raw.map { $0.cleaned }.joined(separator: " ")
   let correctedPhrase = correction.enhanced.map { $0.cleaned }.joined(separator: " ")

   guard !rawPhrase.isEmpty, !correctedPhrase.isEmpty else { return nil }

   guard passesFilters(raw: correction.raw, enhanced: correction.enhanced, rawPhrase: rawPhrase, correctedPhrase: correctedPhrase, commonWords: commonWords) else {
    return nil
   }

   return VocabularyCandidate(rawPhrase: rawPhrase, correctedPhrase: correctedPhrase)
  }
 }

 // MARK: - Tokenization

 private struct Token {
  let original: String
  let normalized: String // lowercased, stripped of punctuation (for comparison)
  let cleaned: String    // original casing, stripped of leading/trailing punctuation (for output)
 }

 private static func tokenize(_ text: String) -> [Token] {
  text.split(separator: " ")
   .map { substring -> Token in
    let original = String(substring)
    let normalized = original
     .lowercased()
     .trimmingCharacters(in: .punctuationCharacters)
    let cleaned = original
     .trimmingCharacters(in: .punctuationCharacters)
    return Token(original: original, normalized: normalized, cleaned: cleaned)
   }
   .filter { !$0.normalized.isEmpty }
 }

 // MARK: - LCS

 private struct LCSPair {
  let rawIndex: Int
  let enhancedIndex: Int
 }

 private static func longestCommonSubsequence(_ a: [String], _ b: [String]) -> [LCSPair] {
  let m = a.count
  let n = b.count
  guard m > 0, n > 0 else { return [] }
  var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

  for i in 1...m {
   for j in 1...n {
    if a[i - 1] == b[j - 1] {
     dp[i][j] = dp[i - 1][j - 1] + 1
    } else {
     dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
    }
   }
  }

  var pairs: [LCSPair] = []
  var i = m, j = n
  while i > 0 && j > 0 {
   if a[i - 1] == b[j - 1] {
    pairs.append(LCSPair(rawIndex: i - 1, enhancedIndex: j - 1))
    i -= 1
    j -= 1
   } else if dp[i - 1][j] > dp[i][j - 1] {
    i -= 1
   } else {
    j -= 1
   }
  }

  return pairs.reversed()
 }

 // MARK: - Correction Extraction

 private struct CorrectionPair {
  let raw: [Token]
  let enhanced: [Token]
 }

 private static func extractCorrections(rawTokens: [Token], enhancedTokens: [Token], lcs: [LCSPair]) -> [CorrectionPair] {
  var corrections: [CorrectionPair] = []
  var rawPos = 0
  var enhancedPos = 0

  for pair in lcs {
   let rawGap = Array(rawTokens[rawPos..<pair.rawIndex])
   let enhancedGap = Array(enhancedTokens[enhancedPos..<pair.enhancedIndex])

   if !rawGap.isEmpty && !enhancedGap.isEmpty {
    corrections.append(CorrectionPair(raw: rawGap, enhanced: enhancedGap))
   }

   rawPos = pair.rawIndex + 1
   enhancedPos = pair.enhancedIndex + 1
  }

  let rawGap = Array(rawTokens[rawPos...])
  let enhancedGap = Array(enhancedTokens[enhancedPos...])
  if !rawGap.isEmpty && !enhancedGap.isEmpty {
   corrections.append(CorrectionPair(raw: rawGap, enhanced: enhancedGap))
  }

  return corrections
 }

 // MARK: - Filters

 private static let fillerWords: Set<String> = Set(FillerWordManager.defaultFillerWords)

 private static func passesFilters(raw: [Token], enhanced: [Token], rawPhrase: String, correctedPhrase: String, commonWords: Set<String>) -> Bool {
  // Skip if raw and corrected are identical (case-insensitive)
  if rawPhrase.lowercased() == correctedPhrase.lowercased() {
   return false
  }

  // Skip runs longer than 4 tokens
  if raw.count > 4 || enhanced.count > 4 {
   return false
  }

  // Skip single-character tokens (both sides)
  if raw.count == 1 && raw[0].normalized.count <= 1 {
   return false
  }
  if enhanced.count == 1 && enhanced[0].normalized.count <= 1 {
   return false
  }

  // Skip if raw tokens are all common filler words
  if raw.allSatisfy({ fillerWords.contains($0.normalized) }) {
   return false
  }

  // Skip if correction is only punctuation/capitalization difference
  if isOnlyPunctuationOrCapitalizationChange(raw: raw, enhanced: enhanced) {
   return false
  }

  // Skip if ALL words in the corrected phrase are common words.
  // Vocabulary suggestions should be for terms Whisper doesn't know --
  // proper nouns, brand names, technical jargon -- not common rephrasing.
  if !commonWords.isEmpty && enhanced.allSatisfy({ commonWords.contains($0.normalized) }) {
   return false
  }

  // Skip if ALL words in the raw phrase are common words.
  // If Whisper produced only common words, it didn't mishear a
  // vocabulary term -- the AI is just rephrasing or inserting content.
  if !commonWords.isEmpty && raw.allSatisfy({ commonWords.contains($0.normalized) }) {
   return false
  }

  return true
 }

 private static func isOnlyPunctuationOrCapitalizationChange(raw: [Token], enhanced: [Token]) -> Bool {
  guard raw.count == enhanced.count else { return false }
  for (r, e) in zip(raw, enhanced) {
   if r.normalized != e.normalized {
    return false
   }
  }
  return true
 }
}
