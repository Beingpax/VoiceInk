import SwiftUI
import AppKit

struct ElevenLabsPromptingView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @State private var newTagToken: String = ""

    private let catalogIndex: [String: ElevenLabsVoiceTag] = {
        Dictionary(uniqueKeysWithValues: ElevenLabsVoiceTag.defaultCatalog.map { ($0.token, $0) })
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Prompting Tools", systemImage: "wand.and.stars")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Compose ElevenLabs v3 prompts, choose a model, and drop inline tags without leaving the editor.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            modelPicker
            promptEditor
            tagsManager

            Text("Voice tags are case-sensitive and must match ElevenLabs documentation exactly. Tags apply to the spoken text that follows, so add them just before the relevant sentence.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Model", systemImage: "brain.head.profile")
                .font(.footnote)
                .foregroundColor(.secondary)

            Picker("ElevenLabs model", selection: $viewModel.elevenLabsModel) {
                ForEach(ElevenLabsModel.allCases) { model in
                    Text(model.displayName).tag(model)
                }
            }
            .pickerStyle(MenuPickerStyle())

            Text(viewModel.elevenLabsModel.detail)
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if viewModel.elevenLabsModel.requiresEarlyAccess {
                Label("Requires ElevenLabs early access", systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
    }

    private var promptEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Voice Prompt", systemImage: "text.append")
                .font(.footnote)
                .foregroundColor(.secondary)

            TextEditor(text: $viewModel.elevenLabsPrompt)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 80, maxHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2))
                )

            HStack(spacing: 8) {
                Button {
                    viewModel.insertElevenLabsPromptAtTop()
                } label: {
                    Label("Insert at top", systemImage: "text.alignleft")
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .disabled(viewModel.elevenLabsPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    copyToPasteboard(viewModel.elevenLabsPrompt)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .disabled(viewModel.elevenLabsPrompt.isEmpty)
            }
        }
    }

    private var tagsManager: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Voice Tags", systemImage: "tag")
                .font(.footnote)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                TextField("Add tag (e.g. [whisper])", text: $newTagToken)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minWidth: 200)

                Button("Add") {
                    addNewTag()
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .disabled(newTagToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()

                Button("Reset") {
                    viewModel.resetElevenLabsTagsToDefaults()
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            }

            if viewModel.elevenLabsTags.isEmpty {
                Text("No saved tags yet. Use Add to store the tokens you reference most.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                    ForEach(viewModel.elevenLabsTags, id: \.self) { token in
                        tagCard(for: token)
                    }
                }
            }
        }
    }

    private func tagCard(for token: String) -> some View {
        let summary = catalogIndex[token]?.summary

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(token)
                    .font(.system(size: 12, design: .monospaced))
                Spacer(minLength: 4)
                Menu {
                    Button("Insert in editor") {
                        viewModel.insertElevenLabsTag(token)
                    }
                    Button("Copy to clipboard") {
                        copyToPasteboard(token)
                    }
                    Divider()
                    Button("Remove", role: .destructive) {
                        viewModel.removeElevenLabsTag(token)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 12))
                }
                .menuStyle(BorderlessButtonMenuStyle())
            }

            if let summary {
                Text(summary)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func addNewTag() {
        let trimmed = newTagToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.addElevenLabsTag(trimmed)
        newTagToken = ""
    }

    private func copyToPasteboard(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmed, forType: .string)
    }
}
