import SwiftUI
import SwiftData

enum VocabularySortMode: String {
    case wordAsc = "wordAsc"
    case wordDesc = "wordDesc"
}

struct CustomVocabularyView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VocabularyWord.word) private var allVocabularyWords: [VocabularyWord]

    @State private var newWord = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var sortMode: VocabularySortMode = .wordAsc

    init() {
        if let savedSort = UserDefaults.standard.string(forKey: "vocabularySortMode"),
           let mode = VocabularySortMode(rawValue: savedSort) {
            _sortMode = State(initialValue: mode)
        }
    }

    private var sortedItems: [VocabularyWord] {
        switch sortMode {
        case .wordAsc:
            return allVocabularyWords.sorted { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending }
        case .wordDesc:
            return allVocabularyWords.sorted { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedDescending }
        }
    }

    private func toggleSort() {
        sortMode = (sortMode == .wordAsc) ? .wordDesc : .wordAsc
        UserDefaults.standard.set(sortMode.rawValue, forKey: "vocabularySortMode")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox {
                Label {
                    Text("Add words to help VoiceInk recognize them properly. (Requires AI enhancement)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                }
            }

            HStack(spacing: 8) {
                TextField("Add word to vocabulary", text: $newWord)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .onSubmit { addWords() }

                Button(action: addWords) {
                    Image(systemName: "plus.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.blue)
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .disabled(newWord.isEmpty)
                .help("Add word")
            }

            if !allVocabularyWords.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Button(action: toggleSort) {
                        HStack(spacing: 4) {
                            Text("Vocabulary Words (\(allVocabularyWords.count))")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)

                            Image(systemName: sortMode == .wordAsc ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Sort alphabetically")

                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: .infinity), spacing: 12)], alignment: .leading, spacing: 12) {
                            ForEach(sortedItems, id: \.word) { item in
                                VocabularyWordView(word: item.word) {
                                    removeWord(item)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 200)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .alert("Custom Vocabulary", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private func addWords() {
        let input = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        let parts = input
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else { return }

        if parts.count == 1, let word = parts.first {
            if allVocabularyWords.contains(where: { $0.word.lowercased() == word.lowercased() }) {
                alertMessage = "'\(word)' is already in the vocabulary"
                showAlert = true
                return
            }
            addWord(word)
            newWord = ""
            return
        }

        for word in parts {
            let lower = word.lowercased()
            if !allVocabularyWords.contains(where: { $0.word.lowercased() == lower }) {
                addWord(word)
            }
        }
        newWord = ""
    }

    private func addWord(_ word: String) {
        let vocabularyWord = VocabularyWord(word: word)
        modelContext.insert(vocabularyWord)

        do {
            try modelContext.save()
        } catch {
            alertMessage = "Failed to add word: \(error.localizedDescription)"
            showAlert = true
        }
    }

    private func removeWord(_ item: VocabularyWord) {
        modelContext.delete(item)

        do {
            try modelContext.save()
        } catch {
            alertMessage = "Failed to remove word: \(error.localizedDescription)"
            showAlert = true
        }
    }
}

struct VocabularyWordView: View {
    let word: String
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Text(word)
                .font(.system(size: 13))
                .lineLimit(1)
                .foregroundColor(.primary)

            Spacer(minLength: 8)

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isHovered ? .red : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .help("Remove word")
            .onHover { hover in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hover
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.windowBackgroundColor).opacity(0.4))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
    }
}
