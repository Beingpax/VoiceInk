import SwiftUI

struct TextSnippetsView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @State private var isPresentingAddSheet = false
    @State private var snippetName: String = ""

    private var defaultSnippetName: String {
        let trimmed = viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let firstLine = trimmed.split(separator: "\n").first.map(String.init) ?? trimmed
        return String(firstLine.prefix(40))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: viewModel.isMinimalistMode ? 8 : 12) {
            HStack {
                Label("Saved Snippets", systemImage: "text.append")
                    .font(.headline)

                Spacer()

                Button {
                    snippetName = defaultSnippetName
                    isPresentingAddSheet = true
                } label: {
                    if viewModel.isMinimalistMode {
                        Label("Save Current Text", systemImage: "plus")
                            .labelStyle(.iconOnly)
                    } else {
                        Label("Save Current Text", systemImage: "plus")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if viewModel.textSnippets.isEmpty {
                Text("Store frequently used scripts here for instant reuse.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(viewModel.textSnippets) { snippet in
                    SnippetRow(snippet: snippet)
                        .environmentObject(viewModel)
                        .transition(.opacity)
                }
            }
        }
        .padding(viewModel.isMinimalistMode ? 10 : 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .animation(.easeInOut(duration: 0.2), value: viewModel.textSnippets)
        .sheet(isPresented: $isPresentingAddSheet) {
            AddSnippetSheet(isPresented: $isPresentingAddSheet, snippetName: snippetName)
                .environmentObject(viewModel)
        }
    }
}

private struct SnippetRow: View {
    @EnvironmentObject var viewModel: TTSViewModel
    let snippet: TextSnippet
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(snippet.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Text(snippet.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(snippet.previewText)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                Button {
                    viewModel.insertSnippet(snippet, mode: .replace)
                } label: {
                    Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)

                Button {
                    viewModel.insertSnippet(snippet, mode: .append)
                } label: {
                    Label("Append", systemImage: "plus.rectangle.on.rectangle")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(role: .destructive) {
                    viewModel.removeSnippet(snippet)
                } label: {
                    Label("Delete", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Color(NSColor.windowBackgroundColor).opacity(0.6) : Color.clear)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct AddSnippetSheet: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @Binding var isPresented: Bool
    @State var snippetName: String
    @State private var validationMessage: String?

    private var trimmedName: String {
        snippetName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save Snippet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Provide a name for this snippet. The current editor text will be saved.")
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("Snippet Name", text: $snippetName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(saveSnippet)

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                Button("Save") {
                    saveSnippet()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 320, minHeight: 220)
    }

    private func saveSnippet() {
        let trimmed = trimmedName
        if trimmed.isEmpty {
            validationMessage = "Name cannot be empty."
            return
        }

        if viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            validationMessage = "There is no text to save."
            return
        }

        viewModel.saveCurrentTextAsSnippet(named: trimmed)
        isPresented = false
    }
}

struct TextSnippetsView_Previews: PreviewProvider {
    static var previews: some View {
        TextSnippetsView()
            .environmentObject(TTSViewModel())
            .padding()
            .frame(width: 600)
    }
}
