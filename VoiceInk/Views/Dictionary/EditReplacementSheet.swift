import SwiftUI
// Edit existing word replacement entry
struct EditReplacementSheet: View {
    @ObservedObject var manager: WordReplacementManager
    let originalKey: String

    @Environment(\.dismiss) private var dismiss

    @State private var originalWord: String
    @State private var replacementWord: String
    @State private var showAlert = false
    @State private var alertMessage = ""

    // MARK: – Initialiser
    init(manager: WordReplacementManager, originalKey: String) {
        self.manager = manager
        self.originalKey = originalKey
        _originalWord = State(initialValue: originalKey)
        _replacementWord = State(initialValue: manager.replacements[originalKey] ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
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
        .background(CardBackground(isSelected: false))
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
                            .stroke(Color(.separatorColor), lineWidth: 1)
                    )
            }
            .padding(.horizontal)
        }
    }

    // MARK: – Actions
    private func saveChanges() {
        let newOriginal = originalWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let newReplacement = replacementWord
        let tokens = newOriginal
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty, !newReplacement.isEmpty else { return }

        let result = manager.updateReplacement(oldOriginal: originalKey, newOriginal: newOriginal, newReplacement: newReplacement)
        if result.success {
            dismiss()
        } else {
            if let conflictingWord = result.conflictingWord {
                alertMessage = "'\(conflictingWord)' already exists in word replacements"
            } else {
                alertMessage = "This word replacement already exists"
            }
            showAlert = true
        }
    }
}

// MARK: – Preview
#if DEBUG
struct EditReplacementSheet_Previews: PreviewProvider {
    static var previews: some View {
        EditReplacementSheet(manager: WordReplacementManager(), originalKey: "hello")
    }
}
#endif