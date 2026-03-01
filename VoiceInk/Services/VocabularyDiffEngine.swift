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

  var corrections = extractCorrections(rawTokens: rawTokens, enhancedTokens: enhancedTokens, lcs: lcsIndices)

  expandCompoundNames(corrections: &corrections, enhancedTokens: enhancedTokens, lcs: lcsIndices)

  var seen = Set<String>()
  return corrections.compactMap { correction -> VocabularyCandidate? in
   let rawPhrase = correction.raw.map { $0.cleaned }.joined(separator: " ")
   let correctedPhrase = correction.enhanced.map { $0.cleaned }.joined(separator: " ")

   guard !rawPhrase.isEmpty, !correctedPhrase.isEmpty else { return nil }

   guard passesFilters(raw: correction.raw, enhanced: correction.enhanced, rawPhrase: rawPhrase, correctedPhrase: correctedPhrase, commonWords: commonWords) else {
    return nil
   }

   let key = correctedPhrase.lowercased()
   guard !seen.contains(key) else { return nil }
   seen.insert(key)

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
  let stripped = stripMarkdownFormatting(text)
  return stripped.split(omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
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

 private static func stripMarkdownFormatting(_ text: String) -> String {
  var result = text
  // Remove bullet points (*, -, bullet) at start of lines
  result = result.replacingOccurrences(of: "(?m)^\\s*[*\\-\u{2022}]\\s+", with: " ", options: .regularExpression)
  // Remove numbered list markers at start of lines
  result = result.replacingOccurrences(of: "(?m)^\\s*\\d+\\.\\s+", with: " ", options: .regularExpression)
  // Remove markdown bold/italic markers
  result = result.replacingOccurrences(of: "[*_]{1,3}", with: "", options: .regularExpression)
  return result
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
  var raw: [Token]
  var enhanced: [Token]
  var enhancedStartIndex: Int
 }

 private static func extractCorrections(rawTokens: [Token], enhancedTokens: [Token], lcs: [LCSPair]) -> [CorrectionPair] {
  var corrections: [CorrectionPair] = []
  var rawPos = 0
  var enhancedPos = 0

  for pair in lcs {
   let rawGap = Array(rawTokens[rawPos..<pair.rawIndex])
   let enhancedGap = Array(enhancedTokens[enhancedPos..<pair.enhancedIndex])

   if !rawGap.isEmpty && !enhancedGap.isEmpty {
    corrections.append(CorrectionPair(raw: rawGap, enhanced: enhancedGap, enhancedStartIndex: enhancedPos))
   }

   rawPos = pair.rawIndex + 1
   enhancedPos = pair.enhancedIndex + 1
  }

  let rawGap = Array(rawTokens[rawPos...])
  let enhancedGap = Array(enhancedTokens[enhancedPos...])
  if !rawGap.isEmpty && !enhancedGap.isEmpty {
   corrections.append(CorrectionPair(raw: rawGap, enhanced: enhancedGap, enhancedStartIndex: enhancedPos))
  }

  return corrections
 }

 // MARK: - Compound Name Expansion

 /// When a correction produces a capitalized word like "Claude", check if the
 /// next LCS-matched token is also capitalized (e.g. "Code") and absorb it
 /// to form the full proper noun "Claude Code".
 private static func expandCompoundNames(corrections: inout [CorrectionPair], enhancedTokens: [Token], lcs: [LCSPair]) {
  let matchedEnhancedIndices = Set(lcs.map { $0.enhancedIndex })

  for i in corrections.indices {
   let correction = corrections[i]

   // Only expand if the corrected phrase contains at least one capitalized word
   guard correction.enhanced.contains(where: { $0.cleaned.first?.isUppercase == true }) else { continue }

   // Look at tokens immediately following this correction in the enhanced text
   let enhancedEndIndex = correction.enhancedStartIndex + correction.enhanced.count
   var expandedEnhanced = correction.enhanced
   var nextIndex = enhancedEndIndex

   while nextIndex < enhancedTokens.count {
    // Stop at sentence boundaries -- if the last token ends with . ! ? then the
    // next capitalized word is a new sentence, not part of a compound name
    if let lastOriginal = expandedEnhanced.last?.original,
       let lastChar = lastOriginal.last,
       ".!?".contains(lastChar) {
     break
    }
    let nextToken = enhancedTokens[nextIndex]
    // Only absorb LCS-matched tokens that continue a proper noun phrase (capitalized)
    guard matchedEnhancedIndices.contains(nextIndex),
          nextToken.cleaned.first?.isUppercase == true else { break }
    expandedEnhanced.append(nextToken)
    nextIndex += 1
   }

   if expandedEnhanced.count > correction.enhanced.count {
    corrections[i].enhanced = expandedEnhanced
   }
  }
 }

 // MARK: - Filters

 private static let fillerWords: Set<String> = Set(FillerWordManager.defaultFillerWords)

 private static func passesFilters(raw: [Token], enhanced: [Token], rawPhrase: String, correctedPhrase: String, commonWords: Set<String>) -> Bool {
  // Skip if raw and corrected are identical (case-insensitive)
  if rawPhrase.lowercased() == correctedPhrase.lowercased() {
   return false
  }

  // Skip runs longer than 4 raw tokens or 6 enhanced tokens
  // (enhanced limit is higher to accommodate compound proper nouns from expansion)
  if raw.count > 4 || enhanced.count > 6 {
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
