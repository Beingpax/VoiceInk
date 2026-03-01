import Foundation
import os

class CommonWordsService {
 static let shared = CommonWordsService()

 private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "CommonWords")
 private let lock = OSAllocatedUnfairLock(initialState: [String: Set<String>]())

 private init() {}

 func commonWords(for languageCode: String) -> Set<String> {
  if let cached = lock.withLock({ $0[languageCode] }) {
   return cached
  }

  guard let url = Bundle.main.url(forResource: languageCode, withExtension: "txt") else {
   logger.info("No common words file for language: \(languageCode, privacy: .public)")
   lock.withLock { $0[languageCode] = [] }
   return []
  }

  do {
   let contents = try String(contentsOf: url, encoding: .utf8)
   let words = Set(
    contents
     .components(separatedBy: .newlines)
     .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
     .filter { !$0.isEmpty }
   )
   lock.withLock { $0[languageCode] = words }
   logger.info("Loaded \(words.count, privacy: .public) common words for language: \(languageCode, privacy: .public)")
   return words
  } catch {
   logger.error("Failed to load common words for \(languageCode, privacy: .public): \(error.localizedDescription, privacy: .public)")
   lock.withLock { $0[languageCode] = [] }
   return []
  }
 }
}
