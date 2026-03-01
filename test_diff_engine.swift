#!/usr/bin/env swift
// Standalone test for VocabularyDiffEngine algorithm
// Run with: swift test_diff_engine.swift

import Foundation

// MARK: - Copy of diff engine logic for standalone testing

struct VocabularyCandidate: Hashable, CustomStringConvertible {
 let rawPhrase: String
 let correctedPhrase: String
 var description: String { "\"\(rawPhrase)\" -> \"\(correctedPhrase)\"" }
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

 private static let fillerWords: Set<String> = Set([
  "uh", "um", "uhm", "umm", "uhh", "uhhh", "ah", "eh",
  "hmm", "hm", "mmm", "mm", "mh", "ha", "ehh"
 ])

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

// MARK: - Load common words from file

func loadCommonWords() -> Set<String> {
 let scriptDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
 let wordsFile = scriptDir.appendingPathComponent("VoiceInk/Resources/CommonWords/en.txt")
 guard let contents = try? String(contentsOf: wordsFile, encoding: .utf8) else {
  print("WARNING: Could not load en.txt, common words filter will be empty")
  return []
 }
 return Set(
  contents.components(separatedBy: .newlines)
   .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
   .filter { !$0.isEmpty }
 )
}

let englishCommonWords = loadCommonWords()

// MARK: - Test Harness

func runTest(_ name: String, raw: String, enhanced: String, commonWords: Set<String> = Set<String>(), expectedGood: [String] = [], expectedBad: [String] = []) {
 let candidates = VocabularyDiffEngine.extractCandidates(raw: raw, enhanced: enhanced, commonWords: commonWords)

 print("=== \(name) ===")
 print("  Raw:      \(raw)")
 print("  Enhanced: \(enhanced)")

 if candidates.isEmpty {
  print("  Result:   No candidates (filtered out)")
 } else {
  for c in candidates {
   print("  Found:    \(c)")
  }
 }

 // Check expected good matches
 for expected in expectedGood {
  let found = candidates.contains { $0.correctedPhrase.lowercased() == expected.lowercased() }
  if !found {
   print("  FAIL: Expected to find \"\(expected)\" but didn't")
  }
 }

 // Check expected bad matches (should NOT be found)
 for bad in expectedBad {
  let found = candidates.contains { $0.correctedPhrase.lowercased() == bad.lowercased() }
  if found {
   print("  FAIL: Should NOT have found \"\(bad)\" but did")
  }
 }

 print()
}

// MARK: - Test Cases

print("--- REAL VOCABULARY CORRECTIONS (should find candidates) ---\n")

runTest("Claude Code mishearing",
 raw: "I was using clawed code to help me write the program",
 enhanced: "I was using Claude Code to help me write the program.",
 commonWords: englishCommonWords,
 expectedGood: ["Claude"])  // "code" matches in LCS, so we get just "Claude"

runTest("VoiceInk brand name",
 raw: "I really like voice ink for transcription",
 enhanced: "I really like VoiceInk for transcription.",
 commonWords: englishCommonWords,
 expectedGood: ["VoiceInk"])

runTest("Technical term - Kubernetes",
 raw: "We deployed it on cooper nettys",
 enhanced: "We deployed it on Kubernetes.",
 commonWords: englishCommonWords,
 expectedGood: ["Kubernetes"])

runTest("Person name - Prakash",
 raw: "I talked to per cash about it",
 enhanced: "I talked to Prakash about it.",
 commonWords: englishCommonWords,
 expectedGood: ["Prakash"])

runTest("API acronym",
 raw: "The rest a pea eye is working now",
 enhanced: "The REST API is working now.",
 commonWords: englishCommonWords,
 expectedGood: ["API"])  // "rest" matches in LCS, so we get just "API"

runTest("Multiple corrections in one text",
 raw: "I used clawed code to fix the voice ink bug",
 enhanced: "I used Claude Code to fix the VoiceInk bug.",
 commonWords: englishCommonWords,
 expectedGood: ["Claude", "VoiceInk"])

print("\n--- AI REPHRASING (should NOT find candidates) ---\n")

runTest("Synonym swap: can -> might",
 raw: "I can do that tomorrow",
 enhanced: "I might do that tomorrow.",
 commonWords: englishCommonWords,
 expectedBad: ["might"])

runTest("Rephrasing: figure out -> see",
 raw: "Let me figure out how to do this",
 enhanced: "Let me see how to do this.",
 commonWords: englishCommonWords,
 expectedBad: ["see"])

runTest("Structural: all the people on -> everyone in",
 raw: "all the people on the team agreed",
 enhanced: "Everyone in the team agreed.",
 commonWords: englishCommonWords,
 expectedBad: ["everyone in", "Everyone in"])

runTest("Contraction expansion",
 raw: "and I think we should go",
 enhanced: "I'm also thinking we should go.",
 commonWords: englishCommonWords,
 expectedBad: ["I'm also"])

runTest("Common word swap: then -> using",
 raw: "I was then working on it",
 enhanced: "I was using it for work.",
 commonWords: englishCommonWords,
 expectedBad: ["using"])

runTest("Filler removal + rephrasing",
 raw: "uh I think we should uh probably go ahead",
 enhanced: "I think we should probably go ahead.",
 commonWords: englishCommonWords,
 expectedBad: [])

print("\n--- EDGE CASES ---\n")

runTest("Identical text",
 raw: "Hello world this is a test",
 enhanced: "Hello world this is a test",
 commonWords: englishCommonWords)

runTest("Only punctuation changes",
 raw: "Hello world",
 enhanced: "Hello, world!",
 commonWords: englishCommonWords)

runTest("Name at sentence boundary (AI restructured)",
 raw: "trying to fix the bug yesterday",
 enhanced: "Jeffrey was fixing the bug yesterday.",
 commonWords: englishCommonWords,
 expectedBad: ["Jeffrey was fixing"])  // Raw is all common words + structure changed = rephrasing

runTest("Name as genuine phonetic correction",
 raw: "I talked to Jeffery about the project",
 enhanced: "I talked to Jeffrey about the project.",
 commonWords: englishCommonWords,
 expectedGood: ["Jeffrey"])

runTest("Mixed: real correction + rephrasing",
 raw: "I used clawed code and it can help with many things",
 enhanced: "I used Claude Code and it might help with many things.",
 commonWords: englishCommonWords,
 expectedGood: ["Claude"],
 expectedBad: ["might"])

runTest("Short technical term",
 raw: "the gee pee you is running hot",
 enhanced: "The GPU is running hot.",
 commonWords: englishCommonWords,
 expectedGood: ["GPU"])

runTest("App name with spaces",
 raw: "I opened ex code and started coding",
 enhanced: "I opened Xcode and started coding.",
 commonWords: englishCommonWords,
 expectedGood: ["Xcode"])

print("\n--- GRACEFUL DEGRADATION (empty common words set) ---\n")

runTest("Empty set: rephrasing passes through (expected)",
 raw: "I can do that tomorrow",
 enhanced: "I might do that tomorrow.",
 commonWords: [],
 expectedGood: ["might"])  // Without common words filter, this passes through

runTest("Empty set: real corrections still work",
 raw: "I was using clawed code to help me",
 enhanced: "I was using Claude Code to help me.",
 commonWords: [],
 expectedGood: ["Claude"])

print("\n--- SUMMARY ---")
print("Review the output above to verify the algorithm correctly")
print("identifies vocabulary corrections while filtering out AI rephrasing.")
