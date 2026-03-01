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
     Text("Vocabulary corrections detected from AI enhancement. Approve to add to your dictionary.")
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
      Text("\(suggestions.count) suggestion\(suggestions.count == 1 ? "" : "s")")
       .font(.system(size: 12, weight: .medium))
       .foregroundColor(.secondary)

      Spacer()

      Button(action: approveAll) {
       HStack(spacing: 4) {
        Image(systemName: "checkmark.circle.fill")
         .font(.system(size: 12))
        Text("Approve All")
         .font(.system(size: 12, weight: .medium))
       }
      }
      .buttonStyle(.borderless)
      .foregroundColor(.blue)
     }

     VStack(spacing: 0) {
      HStack(spacing: 8) {
       Text("Misheard")
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)

       Text("Correction")
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
   Text("Suggestions appear when AI enhancement corrects misheard words.")
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
  } catch {
   for word in insertedWords {
    modelContext.delete(word)
   }
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
   HStack(spacing: 4) {
    Text(suggestion.rawPhrase)
     .font(.system(size: 13))
     .strikethrough()
     .foregroundColor(.secondary)
     .lineLimit(2)
   }
   .frame(maxWidth: .infinity, alignment: .leading)

   Image(systemName: "arrow.right")
    .foregroundColor(.secondary)
    .font(.system(size: 10))
    .frame(width: 10)

   ZStack(alignment: .trailing) {
    HStack(spacing: 6) {
     Text(suggestion.correctedPhrase)
      .font(.system(size: 13, weight: .semibold))
      .lineLimit(2)

     if suggestion.occurrenceCount > 1 {
      Text("\(suggestion.occurrenceCount)")
       .font(.system(size: 10, weight: .medium))
       .foregroundColor(.white)
       .padding(.horizontal, 5)
       .padding(.vertical, 1)
       .background(Capsule().fill(.blue.opacity(0.7)))
     }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.trailing, 50)

    HStack(spacing: 6) {
     Button(action: onApprove) {
      Image(systemName: "checkmark.circle.fill")
       .symbolRenderingMode(.hierarchical)
       .foregroundColor(isApproveHovered ? .green : .secondary)
       .contentTransition(.symbolEffect(.replace))
     }
     .buttonStyle(.borderless)
     .help("Approve and add to vocabulary")
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
   .frame(maxWidth: .infinity)
  }
  .padding(.vertical, 8)
  .padding(.horizontal, 4)
 }
}
