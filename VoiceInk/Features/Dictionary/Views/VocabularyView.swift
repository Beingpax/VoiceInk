import SwiftData
import SwiftUI

private struct VocabularyWordDragPayload {
    let term: String
    let sectionID: UUID?

    var encoded: String {
        "\(sectionID?.uuidString ?? "")\n\(term)"
    }

    init(term: String, sectionID: UUID?) {
        self.term = term
        self.sectionID = sectionID
    }

    init?(encoded: String) {
        guard let separator = encoded.firstIndex(of: "\n") else { return nil }
        let sectionText = String(encoded[..<separator])
        if sectionText.isEmpty {
            sectionID = nil
        } else if let sectionID = UUID(uuidString: sectionText) {
            self.sectionID = sectionID
        } else {
            return nil
        }
        term = String(encoded[encoded.index(after: separator)...])
    }
}

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
    @State private var targetedDropTarget: VocabularyDropTarget?

    private struct SectionEditor: Identifiable {
        let id = UUID()
        let section: VocabularySection?
    }

    private enum VocabularyDropTarget: Equatable {
        case noSection
        case section(UUID)

        var sectionID: UUID? {
            switch self {
            case .noSection: nil
            case .section(let id): id
            }
        }
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

            if !vocabularyWords.isEmpty || !vocabularySections.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    if !vocabularyWords.isEmpty {
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
                    }

                    if !vocabularySections.isEmpty {
                        sectionDropTarget(.noSection) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("No section")
                                    .font(.system(size: 12, weight: .semibold))
                                sectionWordFlow(ungroupedWords)
                            }
                        }
                    } else if !ungroupedWords.isEmpty {
                        wordFlow(ungroupedWords)
                    }

                    ForEach(sortedSections) { section in
                        sectionDropTarget(.section(section.id)) {
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
                                sectionWordFlow(sortedItems.filter { $0.sectionID == section.id })
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.top, 4)
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

    private func sectionDropTarget<Content: View>(
        _ target: VocabularyDropTarget,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        targetedDropTarget == target
                            ? Color.accentColor.opacity(0.12)
                            : Color.clear
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        targetedDropTarget == target
                            ? Color.accentColor.opacity(0.8)
                            : Color.clear,
                        style: StrokeStyle(lineWidth: 1, dash: [4])
                    )
            }
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { encodedPayloads, _ in
                guard
                    let encodedPayload = encodedPayloads.first,
                    let payload = VocabularyWordDragPayload(encoded: encodedPayload),
                    let word = vocabularyWords.first(where: {
                        $0.word == payload.term && $0.sectionID == payload.sectionID
                    })
                else {
                    return false
                }

                targetedDropTarget = nil
                guard word.sectionID != target.sectionID else { return true }
                return moveWord(word, to: target.sectionID)
            } isTargeted: { isTargeted in
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isTargeted {
                        targetedDropTarget = target
                    } else if targetedDropTarget == target {
                        targetedDropTarget = nil
                    }
                }
            }
    }

    @ViewBuilder
    private func sectionWordFlow(_ words: [VocabularyWord]) -> some View {
        if words.isEmpty {
            Text("Drop terms here")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        } else {
            wordFlow(words)
        }
    }

    private func wordFlow(_ words: [VocabularyWord]) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(words) { item in
                VocabularyWordView(item: item) {
                    removeWord(item)
                }
                .contentShape(Rectangle())
                .draggable(
                    VocabularyWordDragPayload(term: item.word, sectionID: item.sectionID).encoded
                ) {
                    Color.clear
                        .frame(width: 1, height: 1)
                }
                .help("Drag to move this term to another section")
            }
        }
        .padding(.vertical, 4)
    }

    private func moveWord(_ word: VocabularyWord, to sectionID: UUID?) -> Bool {
        if let error = VocabularySectionService.move(word, to: sectionID, context: modelContext) {
            alertMessage = error
            showAlert = true
            return false
        }
        return true
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
    let onDelete: () -> Void

    var body: some View {
        DictionaryPill(onRemove: onDelete, removeHelp: "Remove word") {
            Text(item.word)
                .lineLimit(1)
        }
    }
}
