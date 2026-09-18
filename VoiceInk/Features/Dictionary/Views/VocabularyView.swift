import SwiftData
import SwiftUI

struct VocabularyView: View {
    @Query private var vocabularyWords: [VocabularyWord]
    @Query private var vocabularySections: [VocabularySection]
    @Environment(\.modelContext) private var modelContext
    @State private var newWord = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var sortMode: VocabularySortMode = .wordAsc
    @State private var showInfoPopover = false
    @State private var selectedSectionID: UUID?
    @State private var sectionEditor: SectionEditor?
    @State private var sectionToDelete: VocabularySection?

    private struct SectionEditor: Identifiable {
        let id = UUID()
        let section: VocabularySection?
    }

    init() {
        _sortMode = State(initialValue: DictionarySortService.shared.savedVocabularyMode())
    }

    private var sortedItems: [VocabularyWord] {
        DictionarySortService.shared.sortVocabulary(vocabularyWords, by: sortMode)
    }

    private var sortedSections: [VocabularySection] {
        vocabularySections.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var ungroupedWords: [VocabularyWord] {
        let sectionIDs = Set(vocabularySections.map(\.id))
        return sortedItems.filter { word in
            guard let sectionID = word.sectionID else { return true }
            return !sectionIDs.contains(sectionID)
        }
    }

    private func toggleSort() {
        let service = DictionarySortService.shared
        sortMode = service.nextVocabularyMode(after: sortMode)
        service.saveVocabularyMode(sortMode)
    }

    private var sortIconName: String {
        switch sortMode {
        case .wordAsc: "chevron.up"
        case .wordDesc: "chevron.down"
        case .newest: "clock.arrow.circlepath"
        case .oldest: "clock"
        }
    }

    private var shouldShowAddButton: Bool {
        !newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("", text: $newWord, prompt: Text("Add word to vocabulary"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .onSubmit { addWords() }
                    .labelsHidden()

                if shouldShowAddButton {
                    AddIconButton(
                        helpText: "Add word",
                        isDisabled: !shouldShowAddButton,
                        action: addWords
                    )
                }

                Button {
                    showInfoPopover.toggle()
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .help("Vocabulary examples")
                .popover(isPresented: $showInfoPopover) {
                    VocabularyInfoPopover()
                }
            }
            .animation(.easeInOut(duration: 0.2), value: shouldShowAddButton)

            HStack {
                if !vocabularySections.isEmpty {
                    Picker("Add to section", selection: $selectedSectionID) {
                        Text("No section").tag(Optional<UUID>.none)
                        ForEach(sortedSections) { section in
                            Text(section.name).tag(Optional(section.id))
                        }
                    }
                    .fixedSize()
                }
                Spacer()
                Button("New section") {
                    sectionEditor = SectionEditor(section: nil)
                }
                .buttonStyle(.borderless)
            }

            if !vocabularyWords.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Button(action: toggleSort) {
                        HStack(spacing: 4) {
                            Text(String(localized: "Vocabulary Words (\(vocabularyWords.count))"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)

                            Image(systemName: sortIconName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Change sort order")

                    if !ungroupedWords.isEmpty {
                        if !vocabularySections.isEmpty {
                            Text("No section")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        wordFlow(ungroupedWords)
                    }

                    ForEach(sortedSections) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(section.name)
                                    .font(.system(size: 13, weight: .semibold))
                                Spacer()
                                Button("Edit") {
                                    sectionEditor = SectionEditor(section: section)
                                }
                                .buttonStyle(.borderless)
                                Button("Delete") {
                                    sectionToDelete = section
                                }
                                .buttonStyle(.borderless)
                            }
                            if !section.sectionDescription.isEmpty {
                                Text(section.sectionDescription)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            wordFlow(sortedItems.filter { $0.sectionID == section.id })
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.top, 4)
            } else {
                ForEach(sortedSections) { section in
                    HStack {
                        Text(section.name)
                        if !section.sectionDescription.isEmpty {
                            Text(section.sectionDescription).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit") { sectionEditor = SectionEditor(section: section) }
                        Button("Delete") { sectionToDelete = section }
                    }
                    .font(.system(size: 12))
                }
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .alert("Vocabulary", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .sheet(item: $sectionEditor) { editor in
            VocabularySectionEditor(section: editor.section)
        }
        .confirmationDialog(
            "Delete section?",
            isPresented: Binding(
                get: { sectionToDelete != nil },
                set: { if !$0 { sectionToDelete = nil } }
            )
        ) {
            Button("Delete section", role: .destructive) {
                if let sectionToDelete {
                    if let error = VocabularySectionService.delete(
                        sectionToDelete, words: vocabularyWords, context: modelContext
                    ) {
                        alertMessage = error
                        showAlert = true
                    }
                    if selectedSectionID == sectionToDelete.id { selectedSectionID = nil }
                    self.sectionToDelete = nil
                }
            }
        } message: {
            Text("Its words will stay in your vocabulary without a section.")
        }
    }

    private func wordFlow(_ words: [VocabularyWord]) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(words) { item in
                VocabularyWordView(item: item, sections: sortedSections) { sectionID in
                    if let error = VocabularySectionService.move(item, to: sectionID, context: modelContext) {
                        alertMessage = error
                        showAlert = true
                    }
                } onDelete: {
                    removeWord(item)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func addWords() {
        let input = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        if let error = DictionaryService.addVocabularyWords(
            input,
            existing: Array(vocabularyWords),
            context: modelContext,
            sectionID: selectedSectionID.flatMap { id in
                vocabularySections.contains(where: { $0.id == id }) ? id : nil
            })
        {
            alertMessage = error
            showAlert = true
            return
        }
        newWord = ""
    }

    private func removeWord(_ word: VocabularyWord) {
        if let error = DictionaryService.removeVocabularyWord(word, context: modelContext) {
            alertMessage = error
            showAlert = true
        }
    }
}

struct VocabularyInfoPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How to use Vocabulary")
                .font(.headline)

            Text(
                "Vocabulary helps supported transcription models and AI enhancement preserve important names, technical terms, and unique spellings."
            )
            .font(.subheadline)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Text("Add one entry at a time, or paste multiple entries separated by commas.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Text("Examples")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(verbatim: "Prakash, VoiceInk, SwiftData, WebSocket")
                .font(.callout)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.textBackgroundColor))
                .cornerRadius(6)
        }
        .padding()
        .frame(width: 320)
    }
}

struct VocabularyWordView: View {
    let item: VocabularyWord
    let sections: [VocabularySection]
    let onMove: (UUID?) -> Void
    let onDelete: () -> Void
    @State private var isDeleteHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Text(item.word)
                .font(.system(size: 13))
                .lineLimit(1)
                .foregroundColor(.primary)

            if !sections.isEmpty {
                Menu {
                    Button("No section") { onMove(nil) }
                    ForEach(sections) { section in
                        Button(section.name) { onMove(section.id) }
                    }
                } label: {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Move word to section")
            }

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isDeleteHovered ? AppTheme.Status.error : .secondary)
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
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(AppTheme.Surface.window.opacity(0.4))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(AppTheme.Border.subtle, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
    }
}
