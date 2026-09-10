import SwiftData
import SwiftUI

// Edit existing word replacement entry
struct EditReplacementSheet: View {
    let replacement: WordReplacement
    let modelContext: ModelContext

    @Environment(\.dismiss) private var dismiss

    @State private var originalWord: String
    @State private var replacementWord: String
    @State private var showAlert = false
    @State private var alertMessage = ""

    // MARK: – Initialiser
    init(replacement: WordReplacement, modelContext: ModelContext) {
        self.replacement = replacement
        self.modelContext = modelContext
        _originalWord = State(initialValue: replacement.originalText)
        _replacementWord = State(initialValue: replacement.replacementText)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .overlay(Divider().opacity(0.5), alignment: .bottom)
            formContent
        }
        .frame(width: 460, height: 560)
        .alert("Word Replacement", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: – Subviews
    private var header: some View {
        HStack {
            Button("Cancel", role: .cancel) { dismiss() }
                .buttonStyle(.borderless)
                .keyboardShortcut(.escape, modifiers: [])

            Spacer()

            Text("Edit Word Replacement")
                .font(.headline)

            Spacer()

            Button("Save") { saveChanges() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(originalWord.isEmpty || replacementWord.isEmpty)
                .keyboardShortcut(.return, modifiers: [])
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(AppCardBackground(isSelected: false, cornerRadius: 16))
    }

    private var formContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                descriptionSection
                inputSection
            }
            .padding(.vertical)
        }
    }

    private var descriptionSection: some View {
        Text("Update the word or phrase that should be automatically replaced.")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, 8)
    }

    private var inputSection: some View {
        VStack(spacing: 16) {
            // Original Text Field
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Original Text")
                        .font(.headline)
                    Text("Required")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                TextField("Enter word or phrase to replace (use commas for multiple)", text: $originalWord)
                    .textFieldStyle(.roundedBorder)

            }
            .padding(.horizontal)

            // Replacement Text Field
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Replacement Text")
                        .font(.headline)
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
                            .stroke(AppTheme.Border.control, lineWidth: 1)
                    )
            }
            .padding(.horizontal)
        }
    }

    // MARK: – Actions
    private func saveChanges() {
        guard !WordReplacementVariants.parse(originalWord).isEmpty,
            !replacementWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        let descriptor = FetchDescriptor<WordReplacement>()
        guard let allReplacements = try? modelContext.fetch(descriptor) else {
            alertMessage = String(localized: "Failed to load word replacements")
            showAlert = true
            return
        }

        if let error = DictionaryService.updateWordReplacement(
            replacement,
            original: originalWord,
            replacementText: replacementWord,
            existing: allReplacements,
            context: modelContext
        ) {
            alertMessage = error
            showAlert = true
            return
        }
        dismiss()
    }
}
