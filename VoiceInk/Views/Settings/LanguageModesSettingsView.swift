import SwiftUI
import KeyboardShortcuts

struct LanguageModesSettingsView: View {
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @ObservedObject private var manager = LanguageModeManager.shared
    @State private var isExpanded = false

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                LabeledContent("Cycle Modes Shortcut") {
                    KeyboardShortcuts.Recorder(for: .cycleLanguageMode)
                        .controlSize(.small)
                }

                if manager.modes.isEmpty {
                    Text("Add a mode below to start cycling between language/model combinations.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(manager.modes) { mode in
                        LanguageModeRow(
                            mode: bindingForMode(mode),
                            isActive: manager.activeModeId == mode.id,
                            availableModels: transcriptionModelManager.usableModels,
                            onDelete: { manager.removeMode(id: mode.id) }
                        )
                    }
                }

                Button {
                    let currentModel = transcriptionModelManager.currentTranscriptionModel
                    let supported = currentModel?.supportedLanguages.keys
                    let language: String = {
                        if let supported = supported {
                            if supported.contains("en") { return "en" }
                            if supported.contains("auto") { return "auto" }
                            return supported.first ?? "en"
                        }
                        return "en"
                    }()
                    let newMode = LanguageMode(
                        transcriptionModelName: currentModel?.name,
                        language: language
                    )
                    manager.addMode(newMode)
                } label: {
                    Label("Add Mode", systemImage: "plus.circle")
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Language Modes")
                    InfoTip("Define a list of model + language presets, then cycle through them with a single shortcut.")
                }
            }
        } header: {
            Text("Language Modes")
        }
    }

    private func bindingForMode(_ mode: LanguageMode) -> Binding<LanguageMode> {
        Binding(
            get: {
                manager.modes.first(where: { $0.id == mode.id }) ?? mode
            },
            set: { updated in
                manager.updateMode(updated)
            }
        )
    }
}

private struct LanguageModeRow: View {
    @Binding var mode: LanguageMode
    let isActive: Bool
    let availableModels: [any TranscriptionModel]
    let onDelete: () -> Void

    private var selectedModel: (any TranscriptionModel)? {
        guard let name = mode.transcriptionModelName else { return nil }
        return availableModels.first { $0.name == name }
    }

    private var supportedLanguages: [(key: String, value: String)] {
        let languages = selectedModel?.supportedLanguages ?? LanguageDictionary.all
        return languages.sorted { lhs, rhs in
            if lhs.key == "auto" { return true }
            if rhs.key == "auto" { return false }
            return lhs.value < rhs.value
        }
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                    }
                    Text(mode.emoji)
                    Text(mode.displayName)
                        .fontWeight(.medium)
                    Spacer()
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }

                LabeledContent("Model") {
                    Picker("", selection: Binding(
                        get: { mode.transcriptionModelName ?? "" },
                        set: { newValue in
                            mode.transcriptionModelName = newValue.isEmpty ? nil : newValue
                            if let model = availableModels.first(where: { $0.name == newValue }),
                               !model.supportedLanguages.keys.contains(mode.language) {
                                mode.language = model.supportedLanguages.keys.contains("auto") ? "auto" : (model.supportedLanguages.keys.first ?? "en")
                            }
                        }
                    )) {
                        Text("Keep Current").tag("")
                        ForEach(availableModels, id: \.name) { model in
                            Text(model.displayName).tag(model.name)
                        }
                    }
                    .labelsHidden()
                }

                LabeledContent("Language") {
                    Picker("", selection: $mode.language) {
                        ForEach(supportedLanguages, id: \.key) { key, value in
                            Text(value).tag(key)
                        }
                    }
                    .labelsHidden()
                }
            }
            .padding(.vertical, 2)
        }
    }
}
