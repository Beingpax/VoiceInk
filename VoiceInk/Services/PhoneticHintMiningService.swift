import Foundation
import SwiftData
import os

struct HintSuggestion {
 let wordText: String
 let wordPersistentModelID: PersistentIdentifier
 let existingHints: String
 let discoveredHints: [String]
}

class PhoneticHintMiningService {
 static let shared = PhoneticHintMiningService()

 private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "PhoneticHintMining")
 private var modelContainer: ModelContainer?

 private init() {}

 func configure(modelContainer: ModelContainer) {
  self.modelContainer = modelContainer
 }

 func mineFromHistory() async -> [HintSuggestion] {
  guard let modelContainer = modelContainer else {
   logger.error("PhoneticHintMiningService not configured")
   return []
  }

  let context = ModelContext(modelContainer)

  let wordDescriptor = FetchDescriptor<VocabularyWord>()
  guard let vocabWords = try? context.fetch(wordDescriptor), !vocabWords.isEmpty else {
   return []
  }

  let vocabLookup = Dictionary(
   vocabWords.map { ($0.word.lowercased(), $0) },
   uniquingKeysWith: { first, _ in first }
  )

  var transcriptionDescriptor = FetchDescriptor<Transcription>(
   predicate: #Predicate { $0.enhancedText != nil }
  )
  transcriptionDescriptor.propertiesToFetch = [\.text, \.enhancedText]
  guard let transcriptions = try? context.fetch(transcriptionDescriptor) else {
   return []
  }

  var languageCode = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "en"
  if languageCode == "auto" {
   languageCode = "en"
  }
  let commonWords = CommonWordsService.shared.commonWords(for: languageCode)

  // Map: lowercased vocab word -> set of discovered raw phrases
  var discoveredHints: [String: Set<String>] = [:]

  for transcription in transcriptions {
   let rawText = transcription.text
   guard let enhancedText = transcription.enhancedText,
         !enhancedText.isEmpty,
         !enhancedText.hasPrefix("Enhancement failed:") else {
    continue
   }

   let candidates = VocabularyDiffEngine.extractCandidates(
    raw: rawText,
    enhanced: enhancedText,
    commonWords: commonWords
   )

   for candidate in candidates {
    let correctedLower = candidate.correctedPhrase.lowercased()
    guard vocabLookup[correctedLower] != nil else { continue }

    let rawPhrase = candidate.rawPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !rawPhrase.isEmpty,
          rawPhrase.lowercased() != correctedLower,
          Self.isPlausiblePhoneticHint(raw: rawPhrase, corrected: candidate.correctedPhrase) else { continue }

    discoveredHints[correctedLower, default: []].insert(rawPhrase.lowercased())
   }
  }

  var suggestions: [HintSuggestion] = []

  for (wordLower, rawPhrases) in discoveredHints {
   guard let vocabWord = vocabLookup[wordLower] else { continue }

   let existingSet = parseHints(vocabWord.phoneticHints)
   let newHints = rawPhrases.subtracting(existingSet)
   guard !newHints.isEmpty else { continue }

   suggestions.append(HintSuggestion(
    wordText: vocabWord.word,
    wordPersistentModelID: vocabWord.persistentModelID,
    existingHints: vocabWord.phoneticHints,
    discoveredHints: newHints.sorted()
   ))
  }

  return suggestions.sorted { $0.wordText.localizedCaseInsensitiveCompare($1.wordText) == .orderedAscending }
 }

 static func mergeHints(existing: String, new: [String]) -> String {
  let existingParts = existing
   .split(separator: ",")
   .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
   .filter { !$0.isEmpty }

  let existingLower = Set(existingParts.map { $0.lowercased() })

  var merged = existingParts
  for hint in new {
   let trimmed = hint.trimmingCharacters(in: .whitespacesAndNewlines)
   guard !trimmed.isEmpty,
         !existingLower.contains(trimmed.lowercased()) else { continue }
   merged.append(trimmed)
  }

  return merged.joined(separator: ", ")
 }

 // MARK: - Phonetic Plausibility Filter

 /// Determines whether a raw phrase is a plausible phonetic mishearing of the
 /// corrected vocabulary word. Rejects morphological variants, number/format
 /// expansions, abbreviations, containment patterns, and pairs with too little
 /// character overlap.
 static func isPlausiblePhoneticHint(raw: String, corrected: String) -> Bool {
  let rawLower = raw.lowercased()
  let correctedLower = corrected.lowercased()

  let rawAlpha = rawLower.filter { $0.isLetter || $0.isNumber }
  let correctedAlpha = correctedLower.filter { $0.isLetter || $0.isNumber }
  guard !rawAlpha.isEmpty, !correctedAlpha.isEmpty else { return false }

  // Reject English morphological variants (skill/skilled, detect/detecting)
  if isMorphologicalVariant(rawAlpha, correctedAlpha) { return false }

  // Reject abbreviations (devs/developers) where the raw is a short prefix
  // of the corrected word. Require the corrected to be at least double the
  // length to distinguish abbreviations from truncated mishearings (avaloni/avalonia).
  let rawBase = rawAlpha.hasSuffix("s") ? String(rawAlpha.dropLast(1)) : rawAlpha
  if rawBase.count >= 3 && correctedAlpha.hasPrefix(rawBase) && correctedAlpha.count >= rawBase.count * 2 {
   return false
  }

  // Reject number-to-text conversions
  let numberWords: Set<String> = [
   "zero", "one", "two", "three", "four", "five", "six", "seven", "eight",
   "nine", "ten", "twenty", "thirty", "forty", "fifty", "sixty", "seventy",
   "eighty", "ninety", "hundred", "thousand", "percent", "half", "quarter"
  ]
  let rawTokens = rawLower.split(whereSeparator: { $0.isWhitespace || $0 == "-" }).map { String($0) }
  let correctedTokens = correctedLower.split(whereSeparator: { $0.isWhitespace || $0 == "-" }).map { String($0) }
  if rawTokens.contains(where: { numberWords.contains($0) }) && correctedAlpha.contains(where: { $0.isNumber }) {
   return false
  }

  // Reject if raw contains the corrected word (or its main token) verbatim
  // plus extra words -- this is context leakage, not a mishearing.
  // e.g. "quick please" contains "quick" which is the root of "quickly",
  //      "slash ideation" contains "ideation", "have.net" contains "net"
  if containsVocabWord(rawTokens: rawTokens, correctedTokens: correctedTokens) {
   return false
  }

  // Reject if raw starts with "slash" and corrected starts with "/" or "`/"
  if rawTokens.first == "slash" && (correctedLower.hasPrefix("/") || correctedLower.hasPrefix("`/")) {
   return false
  }

  // Reject if token count differs by more than 1
  if abs(rawTokens.count - correctedTokens.count) > 1 { return false }

  // Character overlap via bigram Dice coefficient.
  // Threshold 0.30 -- balances catching genuine mishearings (chambois/chezmoi
  // scores 0.31) while rejecting garbled artifacts.
  let similarity = bigramSimilarity(rawAlpha, correctedAlpha)
  if similarity < 0.30 { return false }

  return true
 }

 /// Checks if two alpha strings are morphological variants of each other
 /// (e.g. skill/skilled, pasting/paste, cursor/cursors).
 private static func isMorphologicalVariant(_ a: String, _ b: String) -> Bool {
  let (shorter, longer) = a.count <= b.count ? (a, b) : (b, a)
  guard shorter.count >= 3 else { return false }

  // Check common English suffixes
  let suffixes = ["ed", "ing", "ly", "er", "est", "s", "es", "tion", "sion"]
  for suffix in suffixes {
   if longer.hasSuffix(suffix) {
    let stem = String(longer.dropLast(suffix.count))
    // stem matches shorter, or shorter matches stem + common connector
    if stem == shorter { return true }
    // Handle consonant doubling (e.g. "run" -> "running")
    if stem.count > 0 && String(stem.dropLast(1)) == shorter { return true }
    // Handle e-drop (e.g. "paste" -> "pasting")
    if shorter.hasSuffix("e") && String(shorter.dropLast(1)) == stem { return true }
   }
  }

  // Check possessive
  if longer.hasSuffix("s") && String(longer.dropLast(1)) == shorter { return true }

  return false
 }

 /// Returns true if the raw phrase contains the corrected word (or a main
 /// token of it) as a whole word, indicating context leakage rather than
 /// a genuine mishearing. Only triggers when raw has MORE words than corrected
 /// (extra context words added), not when one word is merely split/respelled
 /// into multiple tokens. Splits on dots/punctuation too (for "have.net").
 private static func containsVocabWord(rawTokens: [String], correctedTokens: [String]) -> Bool {
  // Split raw tokens further on dots and other punctuation
  let rawSubtokens = rawTokens.flatMap {
   $0.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { String($0) }
  }
  for ct in correctedTokens {
   let ctAlpha = ct.filter { $0.isLetter || $0.isNumber }
   guard ctAlpha.count >= 3 else { continue }
   for rt in rawSubtokens {
    let rtAlpha = rt.filter { $0.isLetter || $0.isNumber }
    // Exact match of a corrected token in raw
    if rtAlpha == ctAlpha { return true }
    // Stem-close match: only flag when the raw phrase has strictly more
    // space-separated words than the corrected phrase. This catches
    // "quick please" -> "quickly" (2 words raw > 1 word corrected) but
    // not "Voice Inc" -> "VoiceInk" (2 raw ~ 1 corrected compound).
    if rawTokens.count >= correctedTokens.count + 1 {
     if rtAlpha.count >= 4 && ctAlpha.count >= 4 {
      if ctAlpha.hasPrefix(rtAlpha) && ctAlpha.count - rtAlpha.count <= 2 { return true }
      if rtAlpha.hasPrefix(ctAlpha) && rtAlpha.count - ctAlpha.count <= 2 { return true }
     }
    }
   }
  }
  return false
 }

 /// Dice coefficient over character bigrams. Returns 0.0...1.0.
 private static func bigramSimilarity(_ a: String, _ b: String) -> Double {
  func bigrams(_ s: String) -> [String] {
   let chars = Array(s)
   guard chars.count >= 2 else { return [s] }
   return (0..<chars.count - 1).map { String(chars[$0...$0+1]) }
  }
  let aBigrams = bigrams(a)
  let bBigrams = bigrams(b)
  guard !aBigrams.isEmpty, !bBigrams.isEmpty else { return 0 }
  var bCounts: [String: Int] = [:]
  for bg in bBigrams { bCounts[bg, default: 0] += 1 }
  var matches = 0
  for bg in aBigrams {
   if let count = bCounts[bg], count > 0 {
    matches += 1
    bCounts[bg] = count - 1
   }
  }
  return Double(2 * matches) / Double(aBigrams.count + bBigrams.count)
 }

 private func parseHints(_ hints: String) -> Set<String> {
  Set(
   hints
    .split(separator: ",")
    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    .filter { !$0.isEmpty }
  )
 }
}
