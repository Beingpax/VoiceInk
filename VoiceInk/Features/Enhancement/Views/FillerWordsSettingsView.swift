import SwiftUI

struct FillerWordChip: View {
    let word: String
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Text(word)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundColor(.primary)

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isHovered ? AppTheme.Status.error : .secondary)
                    .font(.system(size: 10))
            }
            .buttonStyle(.borderless)
            .onHover { hover in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hover
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(AppTheme.Surface.window.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(AppTheme.Border.subtle, lineWidth: 1)
        )
    }
}

struct FillerWordsSettingsSection: View {
    @StateObject private var fillerWordManager = FillerWordManager.shared
    @State private var newWord = ""
    @State private var isShowingAddWord = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            if !fillerWordManager.fillerWords.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(fillerWordManager.fillerWords, id: \.self) { word in
                        FillerWordChip(word: word) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                fillerWordManager.removeWord(word)
                            }
                        }
                    }
                }
            }
        } header: {
            HStack {
                HStack(spacing: 4) {
                    Text("Remove Filler Words")
                    InfoTip(
                        "Automatically remove configured filler words like 'uh', 'um', or 'hmm' from transcriptions. If no filler words are configured, this cleanup is skipped."
                    )
                }

                Spacer()

                AddIconButton(helpText: "Add filler word") {
                    newWord = ""
                    errorMessage = nil
                    isShowingAddWord = true
                }
                .popover(isPresented: $isShowingAddWord, arrowEdge: .top) {
                    addWordPopover
                }
            }
        }
    }

    private var addWordPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Filler Word")
                .font(.headline)

            TextField("Filler word", text: $newWord)
                .textFieldStyle(.roundedBorder)
                .onSubmit { addWord() }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Status.error)
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    closeAddWordPopover()
                }

                Button("Add") {
                    addWord()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 260)
    }

    private func closeAddWordPopover() {
        newWord = ""
        errorMessage = nil
        isShowingAddWord = false
    }

    private func addWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = nil
            return
        }

        guard fillerWordManager.addWord(trimmed) else {
            errorMessage = String(localized: "This filler word already exists.")
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            closeAddWordPopover()
        }
    }
}
