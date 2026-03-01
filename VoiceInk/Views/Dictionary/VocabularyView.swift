import SwiftUI
import SwiftData

enum VocabularySortMode: String {
    case wordAsc = "wordAsc"
    case wordDesc = "wordDesc"
}

struct VocabularyView: View {
    @Query private var vocabularyWords: [VocabularyWord]
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var whisperPrompt: WhisperPrompt
    @State private var newWord = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var sortMode: VocabularySortMode = .wordAsc

    init(whisperPrompt: WhisperPrompt) {
        self.whisperPrompt = whisperPrompt

        if let savedSort = UserDefaults.standard.string(forKey: "vocabularySortMode"),
           let mode = VocabularySortMode(rawValue: savedSort) {
            _sortMode = State(initialValue: mode)
        }
    }

    private var sortedItems: [VocabularyWord] {
        switch sortMode {
        case .wordAsc:
            return vocabularyWords.sorted { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending }
        case .wordDesc:
            return vocabularyWords.sorted { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedDescending }
        }
    }

    private func toggleSort() {
        sortMode = (sortMode == .wordAsc) ? .wordDesc : .wordAsc
        UserDefaults.standard.set(sortMode.rawValue, forKey: "vocabularySortMode")
    }

    private var shouldShowAddButton: Bool {
        !newWord.isEmpty
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

                if shouldShowAddButton {
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
            }
            .animation(.easeInOut(duration: 0.2), value: shouldShowAddButton)

            if !vocabularyWords.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Button(action: toggleSort) {
                        HStack(spacing: 4) {
                            Text("Vocabulary Words (\(vocabularyWords.count))")
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
                        FlowLayout(spacing: 8) {
                            ForEach(sortedItems) { item in
                                VocabularyWordView(item: item, onDelete: {
                                    removeWord(item)
                                }, onSave: {
                                    saveContext()
                                })
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
        .alert("Vocabulary", isPresented: $showAlert) {
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
            if vocabularyWords.contains(where: { $0.word.lowercased() == word.lowercased() }) {
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
            if !vocabularyWords.contains(where: { $0.word.lowercased() == lower }) {
                addWord(word)
            }
        }
        newWord = ""
    }

    private func addWord(_ word: String) {
        let normalizedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !vocabularyWords.contains(where: { $0.word.lowercased() == normalizedWord.lowercased() }) else {
            return
        }

        let newWord = VocabularyWord(word: normalizedWord)
        modelContext.insert(newWord)

        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .promptDidChange, object: nil)
        } catch {
            // Rollback the insert to maintain UI consistency
            modelContext.delete(newWord)
            alertMessage = "Failed to add word: \(error.localizedDescription)"
            showAlert = true
        }
    }

    private func saveContext() {
        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .promptDidChange, object: nil)
        } catch {
            alertMessage = "Failed to save: \(error.localizedDescription)"
            showAlert = true
        }
    }

    private func removeWord(_ word: VocabularyWord) {
        modelContext.delete(word)

        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .promptDidChange, object: nil)
        } catch {
            // Rollback the delete to restore UI consistency
            modelContext.rollback()
            alertMessage = "Failed to remove word: \(error.localizedDescription)"
            showAlert = true
        }
    }
}

struct VocabularyWordView: View {
    @Bindable var item: VocabularyWord
    let onDelete: () -> Void
    let onSave: () -> Void
    @State private var isDeleteHovered = false
    @State private var isExpanded = false
    @State private var hintsText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(item.word)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .foregroundColor(.primary)

                if !item.phoneticHints.isEmpty && !isExpanded {
                    Image(systemName: "waveform")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .help("Has phonetic hints: \(item.phoneticHints)")
                }

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                        if isExpanded {
                            hintsText = item.phoneticHints
                        }
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Edit phonetic hints")

                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isDeleteHovered ? .red : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .help("Remove word")
                .onHover { hover in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isDeleteHovered = hover
                    }
                }
            }

            if isExpanded {
                HStack(spacing: 4) {
                    TextField("e.g. clawed code, cloud code", text: $hintsText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                        .onSubmit { saveHints() }

                    Button("Save") { saveHints() }
                        .font(.system(size: 11))
                        .controlSize(.small)
                }
                .padding(.top, 2)
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
                .stroke(item.phoneticHints.isEmpty ? Color.secondary.opacity(0.2) : Color.orange.opacity(0.3), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
    }

    private func saveHints() {
        item.phoneticHints = hintsText.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave()
        withAnimation(.easeInOut(duration: 0.2)) {
            isExpanded = false
        }
    }
} 
