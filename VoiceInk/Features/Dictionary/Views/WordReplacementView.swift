import SwiftData
import SwiftUI

private enum WordReplacementSortColumn {
    case original
    case replacement
}

struct WordReplacementView: View {
    @Query private var wordReplacements: [WordReplacement]
    @Environment(\.modelContext) private var modelContext
    @State private var showAlert = false
    @State private var editingReplacement: WordReplacement? = nil
    @State private var alertMessage = ""
    @State private var sortMode: WordReplacementSortMode = .originalAsc

    init() {
        _sortMode = State(initialValue: DictionarySortService.shared.savedWordReplacementMode())
    }

    private var sortedReplacements: [WordReplacement] {
        DictionarySortService.shared.sortWordReplacements(wordReplacements, by: sortMode)
    }

    private func toggleSort(for column: WordReplacementSortColumn) {
        let service = DictionarySortService.shared
        switch column {
        case .original:
            switch sortMode {
            case .originalAsc: sortMode = .originalDesc
            case .originalDesc: sortMode = .newest
            case .newest: sortMode = .oldest
            case .oldest, .replacementAsc, .replacementDesc: sortMode = .originalAsc
            }
        case .replacement:
            switch sortMode {
            case .replacementAsc: sortMode = .replacementDesc
            case .replacementDesc: sortMode = .newest
            case .newest: sortMode = .oldest
            case .oldest, .originalAsc, .originalDesc: sortMode = .replacementAsc
            }
        }
        service.saveWordReplacementMode(sortMode)
    }

    private var dateSortIconName: String? {
        switch sortMode {
        case .newest: "clock.arrow.circlepath"
        case .oldest: "clock"
        case .originalAsc, .originalDesc, .replacementAsc, .replacementDesc: nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !wordReplacements.isEmpty {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Button(action: { toggleSort(for: .original) }) {
                            HStack(spacing: 4) {
                                Text("Original")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)

                                if sortMode == .originalAsc || sortMode == .originalDesc {
                                    Image(systemName: sortMode == .originalAsc ? "chevron.up" : "chevron.down")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else if let dateSortIconName {
                                    Image(systemName: dateSortIconName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .help("Sort by original")

                        Image(systemName: "arrow.right")
                            .foregroundColor(.secondary)
                            .font(.system(size: 10))
                            .frame(width: 10)

                        Button(action: { toggleSort(for: .replacement) }) {
                            HStack(spacing: 4) {
                                Text("Replacement")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)

                                if sortMode == .replacementAsc || sortMode == .replacementDesc {
                                    Image(systemName: sortMode == .replacementAsc ? "chevron.up" : "chevron.down")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else if let dateSortIconName {
                                    Image(systemName: dateSortIconName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .help("Sort by replacement")
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)

                    Divider()

                    LazyVStack(spacing: 0) {
                        ForEach(sortedReplacements, id: \.persistentModelID) { replacement in
                            ReplacementRow(
                                original: replacement.originalText,
                                replacement: replacement.replacementText,
                                onDelete: { removeReplacement(replacement) },
                                onEdit: { editingReplacement = replacement }
                            )

                            if replacement.persistentModelID != sortedReplacements.last?.persistentModelID {
                                Divider()
                            }
                        }
                    }
                }
                .padding(.top, 4)
            } else {
                Text("No word replacements yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: isEditingReplacement) {
            if let editingReplacement {
                EditReplacementSheet(replacement: editingReplacement, modelContext: modelContext)
            }
        }
        .alert("Word Replacement", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private func removeReplacement(_ replacement: WordReplacement) {
        if let error = DictionaryService.removeWordReplacement(replacement, context: modelContext) {
            alertMessage = error
            showAlert = true
        }
    }

    private var isEditingReplacement: Binding<Bool> {
        Binding(
            get: { editingReplacement != nil },
            set: { isPresented in
                if !isPresented {
                    editingReplacement = nil
                }
            }
        )
    }
}

struct AddWordReplacementPanel: View {
    @Query private var wordReplacements: [WordReplacement]
    @Environment(\.modelContext) private var modelContext
    @FocusState private var focusedField: Field?
    @State private var originalWord = ""
    @State private var replacementWord = ""
    @State private var showAlert = false
    @State private var alertMessage = ""

    let onClose: () -> Void

    private enum Field: Hashable {
        case original
        case replacement
    }

    var body: some View {
        VStack(spacing: 0) {
            AppPanelHeader(title: "Add Word Replacement", onClose: onClose)

            Form {
                Section("Word Replacement") {
                    TextField("Original text (use commas for multiple)", text: $originalWord)
                        .focused($focusedField, equals: .original)

                    TextField("Replacement text", text: $replacementWord)
                        .focused($focusedField, equals: .replacement)
                        .onSubmit { addReplacement() }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Button("Cancel", action: onClose)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add Replacement", action: addReplacement)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAddReplacement)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .overlay(Divider().opacity(0.5), alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { focusedField = .original }
        .alert("Word Replacement", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private var canAddReplacement: Bool {
        !originalWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !replacementWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addReplacement() {
        guard canAddReplacement else { return }

        let original = originalWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = replacementWord.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = DictionaryService.addWordReplacement(
            original: original,
            replacement: replacement,
            existing: Array(wordReplacements),
            context: modelContext
        ) {
            alertMessage = error
            showAlert = true
            return
        }

        onClose()
    }
}

struct WordReplacementInformationContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How to use Word Replacements")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Separate multiple originals with commas:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("Voicing, Voice ink, Voiceing")
                    .font(.callout)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(6)
            }

            Divider()

            Text("Examples")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Original:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("my website link")
                            .font(.callout)
                    }

                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Replacement:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(verbatim: "https://tryvoiceink.com")
                            .font(.callout)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.textBackgroundColor))
                .cornerRadius(6)

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Original:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Voicing, Voice ink")
                            .font(.callout)
                    }

                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Replacement:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("VoiceInk")
                            .font(.callout)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.textBackgroundColor))
                .cornerRadius(6)
            }
        }
        .padding()
        .frame(width: 380)
    }
}

struct ReplacementRow: View {
    let original: String
    let replacement: String
    let onDelete: () -> Void
    let onEdit: () -> Void
    @State private var isEditHovered = false
    @State private var isDeleteHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Text(original)
                .font(.system(size: 13))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.right")
                .foregroundColor(.secondary)
                .font(.system(size: 10))
                .frame(width: 10)

            ZStack(alignment: .trailing) {
                Text(replacement)
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 50)

                HStack(spacing: 6) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(isEditHovered ? AppTheme.Accent.primary : .secondary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.borderless)
                    .help("Edit replacement")
                    .onHover { hover in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEditHovered = hover
                        }
                    }

                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(isDeleteHovered ? AppTheme.Status.error : .secondary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.borderless)
                    .help("Remove replacement")
                    .onHover { hover in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isDeleteHovered = hover
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
