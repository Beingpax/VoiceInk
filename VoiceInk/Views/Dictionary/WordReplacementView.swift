import SwiftUI
import SwiftData

extension String: Identifiable {
    public var id: String { self }
}

enum SortMode: String {
    case originalAsc = "originalAsc"
    case originalDesc = "originalDesc"
    case replacementAsc = "replacementAsc"
    case replacementDesc = "replacementDesc"
}

enum SortColumn {
    case original
    case replacement
}

struct WordReplacementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WordReplacement.originalVariants) private var allReplacements: [WordReplacement]

    @State private var showAddReplacementModal = false
    @State private var showAlert = false
    @State private var editingReplacement: WordReplacement? = nil
    @State private var alertMessage = ""
    @State private var sortMode: SortMode = .originalAsc

    init() {
        if let savedSort = UserDefaults.standard.string(forKey: "wordReplacementSortMode"),
           let mode = SortMode(rawValue: savedSort) {
            _sortMode = State(initialValue: mode)
        }
    }

    private var sortedReplacements: [WordReplacement] {
        switch sortMode {
        case .originalAsc:
            return allReplacements.sorted { $0.originalVariants.localizedCaseInsensitiveCompare($1.originalVariants) == .orderedAscending }
        case .originalDesc:
            return allReplacements.sorted { $0.originalVariants.localizedCaseInsensitiveCompare($1.originalVariants) == .orderedDescending }
        case .replacementAsc:
            return allReplacements.sorted { $0.replacement.localizedCaseInsensitiveCompare($1.replacement) == .orderedAscending }
        case .replacementDesc:
            return allReplacements.sorted { $0.replacement.localizedCaseInsensitiveCompare($1.replacement) == .orderedDescending }
        }
    }

    private func toggleSort(for column: SortColumn) {
        switch column {
        case .original:
            sortMode = (sortMode == .originalAsc) ? .originalDesc : .originalAsc
        case .replacement:
            sortMode = (sortMode == .replacementAsc) ? .replacementDesc : .replacementAsc
        }
        UserDefaults.standard.set(sortMode.rawValue, forKey: "wordReplacementSortMode")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox {
                Label {
                    Text("Define word replacements to automatically replace specific words or phrases")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                }
            }

            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    Button(action: { toggleSort(for: .original) }) {
                        HStack(spacing: 4) {
                            Text("Original")
                                .font(.headline)

                            if sortMode == .originalAsc || sortMode == .originalDesc {
                                Image(systemName: sortMode == .originalAsc ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Image(systemName: "arrow.right")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                        .frame(width: 20)

                    Button(action: { toggleSort(for: .replacement) }) {
                        HStack(spacing: 4) {
                            Text("Replacement")
                                .font(.headline)

                            if sortMode == .replacementAsc || sortMode == .replacementDesc {
                                Image(systemName: sortMode == .replacementAsc ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 8) {
                        Button(action: { showAddReplacementModal = true }) {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                    }
                    .frame(width: 60)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.controlBackgroundColor))

                Divider()

                // Content
                if allReplacements.isEmpty {
                    EmptyStateView(showAddModal: $showAddReplacementModal)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(sortedReplacements.enumerated()), id: \.element.id) { index, replacement in
                                ReplacementRow(
                                    original: replacement.originalVariants,
                                    replacement: replacement.replacement,
                                    onDelete: { deleteReplacement(replacement) },
                                    onEdit: { editingReplacement = replacement }
                                )

                                if index != sortedReplacements.count - 1 {
                                    Divider()
                                        .padding(.leading, 32)
                                }
                            }
                        }
                        .background(Color(.controlBackgroundColor))
                    }
                }
            }
        }
        .padding()
        .sheet(isPresented: $showAddReplacementModal) {
            AddReplacementSheet(modelContext: modelContext)
        }
        .sheet(item: $editingReplacement) { replacement in
            EditReplacementSheet(modelContext: modelContext, replacement: replacement)
        }
        .alert("Word Replacements", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private func deleteReplacement(_ replacement: WordReplacement) {
        modelContext.delete(replacement)

        do {
            try modelContext.save()
        } catch {
            alertMessage = "Failed to delete replacement: \(error.localizedDescription)"
            showAlert = true
        }
    }
}

struct EmptyStateView: View {
    @Binding var showAddModal: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.word.spacing")
                .font(.system(size: 32))
                .foregroundColor(.secondary)

            Text("No Replacements")
                .font(.headline)

            Text("Add word replacements to automatically replace text.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 250)

            Button("Add Replacement") {
                showAddModal = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AddReplacementSheet: View {
    let modelContext: ModelContext
    @Environment(\.dismiss) private var dismiss
    @State private var originalWord = ""
    @State private var replacementWord = ""
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Text("Add Word Replacement")
                    .font(.headline)

                Spacer()

                Button("Add") {
                    addReplacement()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(originalWord.isEmpty || replacementWord.isEmpty)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(CardBackground(isSelected: false))

            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    // Description
                    Text("Define a word or phrase to be automatically replaced.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.top, 8)

                    // Error Message
                    if let errorMessage = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(12)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }

                    // Form Content
                    VStack(spacing: 16) {
                        // Original Text Section
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Original Text")
                                    .font(.headline)
                                    .foregroundColor(.primary)

                                Text("Required")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            TextField("Enter word or phrase to replace (use commas for multiple)", text: $originalWord)
                                .textFieldStyle(.roundedBorder)
                                .font(.body)
                                .onChange(of: originalWord) {
                                    errorMessage = nil
                                }
                            Text("Separate multiple originals with commas, e.g. Voicing, Voice ink, Voiceing")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)

                        // Replacement Text Section
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Replacement Text")
                                    .font(.headline)
                                    .foregroundColor(.primary)

                                Text("Required")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            TextEditor(text: $replacementWord)
                                .font(.body)
                                .frame(height: 100)
                                .padding(8)
                                .background(Color(.textBackgroundColor))
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color(.separatorColor), lineWidth: 1)
                                )
                        }
                        .padding(.horizontal)
                    }

                    // Example Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Examples")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        // Single original -> replacement
                        HStack(spacing: 12) {
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
                                Text("https://tryvoiceink.com")
                                    .font(.callout)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(.textBackgroundColor))
                        .cornerRadius(8)

                        // Comma-separated originals -> single replacement
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Original:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("Voicing, Voice ink, Voiceing")
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(.textBackgroundColor))
                        .cornerRadius(8)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                .padding(.vertical)
            }
        }
        .frame(width: 460, height: 520)
    }

    private func addReplacement() {
        let original = originalWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = replacementWord.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !original.isEmpty && !replacement.isEmpty else { return }

        // Check if a replacement with the same originalVariants already exists (case-insensitive)
        let descriptor = FetchDescriptor<WordReplacement>()
        if let existingReplacements = try? modelContext.fetch(descriptor) {
            let normalizedOriginal = original.lowercased()
            if existingReplacements.contains(where: { $0.originalVariants.lowercased() == normalizedOriginal }) {
                errorMessage = "A replacement rule for '\(original)' already exists. Please edit the existing rule or use a different original text."
                return
            }
        }

        let wordReplacement = WordReplacement(originalVariants: original, replacement: replacement)
        modelContext.insert(wordReplacement)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "Failed to save replacement: \(error.localizedDescription)"
        }
    }
}

struct EditReplacementSheet: View {
    let modelContext: ModelContext
    let replacement: WordReplacement
    @Environment(\.dismiss) private var dismiss
    @State private var originalWord = ""
    @State private var replacementWord = ""

    init(modelContext: ModelContext, replacement: WordReplacement) {
        self.modelContext = modelContext
        self.replacement = replacement
        _originalWord = State(initialValue: replacement.originalVariants)
        _replacementWord = State(initialValue: replacement.replacement)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Text("Edit Word Replacement")
                    .font(.headline)

                Spacer()

                Button("Save") {
                    saveChanges()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(originalWord.isEmpty || replacementWord.isEmpty)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(CardBackground(isSelected: false))

            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    // Form Content
                    VStack(spacing: 16) {
                        // Original Text Section
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Original Text")
                                    .font(.headline)
                                    .foregroundColor(.primary)

                                Text("Required")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            TextField("Enter word or phrase to replace", text: $originalWord)
                                .textFieldStyle(.roundedBorder)
                                .font(.body)
                        }
                        .padding(.horizontal)

                        // Replacement Text Section
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Replacement Text")
                                    .font(.headline)
                                    .foregroundColor(.primary)

                                Text("Required")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            TextEditor(text: $replacementWord)
                                .font(.body)
                                .frame(height: 100)
                                .padding(8)
                                .background(Color(.textBackgroundColor))
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color(.separatorColor), lineWidth: 1)
                                )
                        }
                        .padding(.horizontal)
                    }
                    .padding(.top)
                }
                .padding(.vertical)
            }
        }
        .frame(width: 460, height: 350)
    }

    private func saveChanges() {
        let original = originalWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacementText = replacementWord.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !original.isEmpty && !replacementText.isEmpty else { return }

        replacement.originalVariants = original
        replacement.replacement = replacementText

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Failed to update replacement: \(error)")
        }
    }
}

struct ReplacementRow: View {
    let original: String
    let replacement: String
    let onDelete: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Original Text Container
            HStack {
                Text(original)
                    .font(.body)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(6)
            }
            .frame(maxWidth: .infinity)

            // Arrow
            Image(systemName: "arrow.right")
                .foregroundColor(.secondary)
                .font(.system(size: 12))

            // Replacement Text Container
            HStack {
                Text(replacement)
                    .font(.body)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(6)
            }
            .frame(maxWidth: .infinity)

            // Edit Button
            Button(action: onEdit) {
                Image(systemName: "pencil.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.accentColor)
                    .font(.system(size: 16))
            }
            .buttonStyle(.borderless)
            .help("Edit replacement")

            // Delete Button
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.red)
                    .font(.system(size: 16))
            }
            .buttonStyle(.borderless)
            .help("Remove replacement")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(Color(.controlBackgroundColor))
    }
}
