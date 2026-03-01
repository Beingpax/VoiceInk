import SwiftUI
import SwiftData

struct VocabularySuggestionsView: View {
 @Query(
  filter: #Predicate<VocabularySuggestion> { $0.status == "pending" },
  sort: \VocabularySuggestion.occurrenceCount,
  order: .reverse
 ) private var suggestions: [VocabularySuggestion]

 @Environment(\.modelContext) private var modelContext

 var body: some View {
  VStack(alignment: .leading, spacing: 20) {
   GroupBox {
    Label {
     Text("Words detected from AI enhancement that may improve transcription accuracy. Add them to your dictionary so Whisper recognizes them.")
      .font(.system(size: 12))
      .foregroundColor(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    } icon: {
     Image(systemName: "info.circle.fill")
      .foregroundColor(.blue)
    }
   }

   if suggestions.isEmpty {
    emptyState
   } else {
    VStack(spacing: 12) {
     HStack {
      Text("\(suggestions.count) suggested word\(suggestions.count == 1 ? "" : "s")")
       .font(.system(size: 12, weight: .medium))
       .foregroundColor(.secondary)

      Spacer()

      Button(action: dismissAll) {
       HStack(spacing: 4) {
        Image(systemName: "xmark.circle")
         .font(.system(size: 12))
        Text("Dismiss All")
         .font(.system(size: 12, weight: .medium))
       }
      }
      .buttonStyle(.borderless)
      .foregroundColor(.secondary)

      Button(action: approveAll) {
       HStack(spacing: 4) {
        Image(systemName: "plus.circle.fill")
         .font(.system(size: 12))
        Text("Add All")
         .font(.system(size: 12, weight: .medium))
       }
      }
      .buttonStyle(.borderless)
      .foregroundColor(.blue)
     }

     VStack(spacing: 0) {
      HStack(spacing: 8) {
       Text("Suggested Word")
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.horizontal, 4)
      .padding(.vertical, 8)

      Divider()

      ScrollView {
       LazyVStack(spacing: 0) {
        ForEach(suggestions) { suggestion in
         SuggestionRow(
          suggestion: suggestion,
          onApprove: { approve(suggestion) },
          onDismiss: { dismiss(suggestion) }
         )

         if suggestion.id != suggestions.last?.id {
          Divider()
         }
        }
       }
      }
      .frame(maxHeight: 300)
     }
    }
   }
  }
  .padding()
 }

 private var emptyState: some View {
  VStack(spacing: 8) {
   Image(systemName: "lightbulb")
    .font(.system(size: 28))
    .foregroundColor(.secondary)
   Text("No suggestions yet")
    .font(.headline)
    .foregroundColor(.secondary)
   Text("Suggestions appear when AI enhancement corrects words that Whisper doesn't recognize.")
    .font(.subheadline)
    .foregroundColor(.secondary.opacity(0.7))
    .multilineTextAlignment(.center)
  }
  .frame(maxWidth: .infinity)
  .padding(.vertical, 32)
 }

 private func approve(_ suggestion: VocabularySuggestion) {
  let newWord = VocabularyWord(word: suggestion.correctedPhrase)
  modelContext.insert(newWord)
  suggestion.status = "approved"

  do {
   try modelContext.save()
   NotificationCenter.default.post(name: .promptDidChange, object: nil)
  } catch {
   modelContext.delete(newWord)
   suggestion.status = "pending"
   modelContext.rollback()
  }
 }

 private func dismiss(_ suggestion: VocabularySuggestion) {
  suggestion.status = "dismissed"

  do {
   try modelContext.save()
  } catch {
   suggestion.status = "pending"
   modelContext.rollback()
  }
 }

 private func approveAll() {
  var insertedWords: [VocabularyWord] = []
  for suggestion in suggestions {
   let newWord = VocabularyWord(word: suggestion.correctedPhrase)
   modelContext.insert(newWord)
   insertedWords.append(newWord)
   suggestion.status = "approved"
  }

  do {
   try modelContext.save()
   NotificationCenter.default.post(name: .promptDidChange, object: nil)
  } catch {
   for word in insertedWords {
    modelContext.delete(word)
   }
   modelContext.rollback()
  }
 }

 private func dismissAll() {
  for suggestion in suggestions {
   suggestion.status = "dismissed"
  }

  do {
   try modelContext.save()
  } catch {
   modelContext.rollback()
  }
 }
}

struct SuggestionRow: View {
 let suggestion: VocabularySuggestion
 let onApprove: () -> Void
 let onDismiss: () -> Void
 @State private var isApproveHovered = false
 @State private var isDismissHovered = false

 var body: some View {
  HStack(spacing: 8) {
   VStack(alignment: .leading, spacing: 2) {
    Text(suggestion.correctedPhrase)
     .font(.system(size: 13, weight: .semibold))
     .lineLimit(2)

    if !suggestion.rawPhrase.isEmpty {
     Text("heard as \"\(suggestion.rawPhrase)\"")
      .font(.system(size: 11))
      .foregroundColor(.secondary)
      .lineLimit(1)
    }
   }
   .frame(maxWidth: .infinity, alignment: .leading)

   if suggestion.occurrenceCount > 1 {
    Text("\(suggestion.occurrenceCount)x")
     .font(.system(size: 10, weight: .medium))
     .foregroundColor(.white)
     .padding(.horizontal, 5)
     .padding(.vertical, 1)
     .background(Capsule().fill(.blue.opacity(0.7)))
   }

   HStack(spacing: 6) {
    Button(action: onApprove) {
     Image(systemName: "plus.circle.fill")
      .symbolRenderingMode(.hierarchical)
      .foregroundColor(isApproveHovered ? .green : .secondary)
      .contentTransition(.symbolEffect(.replace))
    }
    .buttonStyle(.borderless)
    .help("Add to dictionary")
    .onHover { hover in
     withAnimation(.easeInOut(duration: 0.2)) {
      isApproveHovered = hover
     }
    }

    Button(action: onDismiss) {
     Image(systemName: "xmark.circle.fill")
      .symbolRenderingMode(.hierarchical)
      .foregroundStyle(isDismissHovered ? .red : .secondary)
      .contentTransition(.symbolEffect(.replace))
    }
    .buttonStyle(.borderless)
    .help("Dismiss suggestion")
    .onHover { hover in
     withAnimation(.easeInOut(duration: 0.2)) {
      isDismissHovered = hover
     }
    }
   }
  }
  .padding(.vertical, 8)
  .padding(.horizontal, 4)
 }
}
