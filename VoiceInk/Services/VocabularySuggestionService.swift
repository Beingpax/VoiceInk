import Foundation
import SwiftData
import os

class VocabularySuggestionService: NSObject {
 static let shared = VocabularySuggestionService()

 private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "VocabularySuggestion")
 private var modelContainer: ModelContainer?

 private override init() {
  super.init()
 }

 func configure(modelContainer: ModelContainer) {
  self.modelContainer = modelContainer

  NotificationCenter.default.addObserver(
   self,
   selector: #selector(handleTranscriptionCompleted(_:)),
   name: .transcriptionCompleted,
   object: nil
  )

  NotificationCenter.default.addObserver(
   self,
   selector: #selector(handleBackgroundEnhancementCompleted(_:)),
   name: .backgroundEnhancementCompleted,
   object: nil
  )
 }

 @objc private func handleTranscriptionCompleted(_ notification: Notification) {
  guard let transcription = notification.object as? Transcription else { return }
  let transcriptionId = transcription.id
  processTranscription(id: transcriptionId)
 }

 @objc private func handleBackgroundEnhancementCompleted(_ notification: Notification) {
  guard let transcriptionId = notification.userInfo?["transcriptionId"] as? UUID else { return }
  // Brief delay to ensure the persistent store has flushed the write from the enhancement queue's context
  Task {
   try? await Task.sleep(nanoseconds: 500_000_000)
   self.processTranscription(id: transcriptionId)
  }
 }

 private func processTranscription(id transcriptionId: UUID) {
  guard UserDefaults.standard.bool(forKey: "vocabularyExtractionEnabled") else { return }
  guard let modelContainer = modelContainer else {
   logger.error("VocabularySuggestionService not configured")
   return
  }

  Task.detached { [weak self] in
   guard let self = self else { return }

   let context = ModelContext(modelContainer)

   let descriptor = FetchDescriptor<Transcription>(
    predicate: #Predicate { $0.id == transcriptionId }
   )

   guard let transcription = try? context.fetch(descriptor).first else {
    self.logger.warning("Transcription \(transcriptionId.uuidString, privacy: .public) not found for vocabulary extraction")
    return
   }

   let rawText = transcription.text
   guard let enhancedText = transcription.enhancedText,
         !enhancedText.isEmpty,
         !enhancedText.hasPrefix("Enhancement failed:") else {
    return
   }

   var languageCode = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "en"
   if languageCode == "auto" {
    languageCode = "en"
   }
   let commonWords = CommonWordsService.shared.commonWords(for: languageCode)
   let candidates = VocabularyDiffEngine.extractCandidates(raw: rawText, enhanced: enhancedText, commonWords: commonWords)
   guard !candidates.isEmpty else { return }

   let existingWords = CustomVocabularyService.shared.existingWords(from: context)

   var didInsertOrUpdate = false

   for candidate in candidates {
    // Skip if already in vocabulary
    if existingWords.contains(candidate.correctedPhrase.lowercased()) {
     continue
    }

    // Check for existing suggestion with same corrected phrase
    let correctedLower = candidate.correctedPhrase.lowercased()
    let suggestionDescriptor = FetchDescriptor<VocabularySuggestion>()
    let existingSuggestions = (try? context.fetch(suggestionDescriptor)) ?? []

    let matchingSuggestion = existingSuggestions.first {
     $0.correctedPhrase.lowercased() == correctedLower
    }

    if let existing = matchingSuggestion {
     if existing.status == "dismissed" {
      continue
     }
     // Increment occurrence count for pending suggestions
     existing.occurrenceCount += 1
     existing.dateLastSeen = Date()
     didInsertOrUpdate = true
    } else {
     let suggestion = VocabularySuggestion(
      correctedPhrase: candidate.correctedPhrase,
      rawPhrase: candidate.rawPhrase
     )
     context.insert(suggestion)
     didInsertOrUpdate = true
    }
   }

   if didInsertOrUpdate {
    do {
     try context.save()
     self.logger.notice("Saved vocabulary suggestions for transcription \(transcriptionId.uuidString, privacy: .public)")

     await MainActor.run {
      NotificationCenter.default.post(name: .vocabularySuggestionsUpdated, object: nil)
     }
    } catch {
     self.logger.error("Failed to save vocabulary suggestions: \(error.localizedDescription, privacy: .public)")
    }
   }
  }
 }
}
