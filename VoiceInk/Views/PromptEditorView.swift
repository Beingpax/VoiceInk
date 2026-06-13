import SwiftUI

struct PromptEditorView: View {
    enum Mode {
        case add
        case edit(CustomPrompt)
        
        static func == (lhs: Mode, rhs: Mode) -> Bool {
            switch (lhs, rhs) {
            case (.add, .add):
                return true
            case let (.edit(prompt1), .edit(prompt2)):
                return prompt1.id == prompt2.id
            default:
                return false
            }
        }
    }
    
    let mode: Mode
    @EnvironmentObject private var enhancementService: AIEnhancementService
    let onDismiss: () -> Void
    let onSave: (CustomPrompt) -> Void
    let onDelete: ((CustomPrompt) -> Void)?
    @State private var title: String
    @State private var promptText: String
    @State private var triggerWords: [String]
    @State private var newTriggerWord = ""
    @State private var useSystemInstructions: Bool
    @State private var showDeleteConfirmation = false

    private var saveButtonTitle: LocalizedStringKey {
        mode == .add ? "Create & Select" : "Save & Select"
    }

    private var editingPrompt: CustomPrompt? {
        if case .edit(let prompt) = mode {
            return prompt
        }
        return nil
    }

    private var canDeletePrompt: Bool {
        editingPrompt != nil && onDelete != nil
    }

    private var isSaveDisabled: Bool {
        return title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    init(
        mode: Mode,
        onDismiss: @escaping () -> Void,
        onSave: @escaping (CustomPrompt) -> Void,
        onDelete: ((CustomPrompt) -> Void)? = nil
    ) {
        self.mode = mode
        self.onDismiss = onDismiss
        self.onSave = onSave
        self.onDelete = onDelete
        switch mode {
        case .add:
            _title = State(initialValue: "")
            _promptText = State(initialValue: "")
            _triggerWords = State(initialValue: [])
            _useSystemInstructions = State(initialValue: true)
        case .edit(let prompt):
            _title = State(initialValue: prompt.title)
            _promptText = State(initialValue: prompt.promptText)
            _triggerWords = State(initialValue: prompt.triggerWords)
            _useSystemInstructions = State(initialValue: prompt.useSystemInstructions)
        }
    }
    
    private func dismissPanel() {
        onDismiss()
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if case .add = mode {
                        templateMenu
                    }

                    instructionsEditor
                    triggerWordsEditor
                    systemTemplateToggle
                }
                .padding(20)
            }

            footer
        }
        .confirmationDialog(
            "Delete Prompt?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deletePrompt()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(String(format: String(localized: "Are you sure you want to delete '%@'? This action cannot be undone."), title))
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                dismissPanel()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .background(AppTheme.Surface.card)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .help("Back")

            TextField("Prompt name", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .semibold))

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay(Divider().opacity(0.5), alignment: .bottom)
    }

    private var systemTemplateToggle: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $useSystemInstructions) {
                HStack(spacing: 4) {
                    Text("Use System Template")
                    InfoTip("If enabled, your instructions are combined with a general-purpose template to improve transcription quality.\n\nDisable for full control over the AI's system prompt (for advanced users).")
                }
            }
            .toggleStyle(.switch)

            Spacer(minLength: 12)
        }
    }

    private var templateMenu: some View {
        Menu {
            ForEach(PromptTemplates.all) { template in
                Button {
                    title = template.title
                    promptText = template.promptText
                    useSystemInstructions = template.useSystemInstructions
                } label: {
                    Text(template.title)
                }
            }
        } label: {
            Label("Template", systemImage: "sparkles")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .help("Start with a template")
    }

    private var instructionsEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $promptText)
                .font(.system(.body, design: .monospaced))
                .frame(height: 440)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(AppCardBackground(cornerRadius: 8))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            if promptText.isEmpty {
                Text("Write prompt instructions")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .allowsHitTesting(false)
            }
        }
    }

    private var triggerWordsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("Trigger Words")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                InfoTip("Say a trigger word at the beginning or end of a transcription to use this prompt for that request. The trigger word is removed before enhancement.")
            }

            HStack(spacing: 8) {
                TextField("Add trigger word", text: $newTriggerWord)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(AppCardBackground(cornerRadius: 7))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .onSubmit(addTriggerWord)

                AddIconButton(
                    helpText: "Add trigger word",
                    isDisabled: normalizedNewTriggerWord == nil,
                    action: addTriggerWord
                )
            }

            if !triggerWords.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(triggerWords, id: \.self) { word in
                        TriggerWordChip(word: word) {
                            triggerWords.removeAll { $0 == word }
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private var footer: some View {
        HStack {
            if canDeletePrompt {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Text("Delete")
                        .frame(minWidth: 90)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.Status.error)
            } else {
                Button("Cancel") {
                    dismissPanel()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                if let savedPrompt = save() {
                    onSave(savedPrompt)
                }
                dismissPanel()
            } label: {
                Text(saveButtonTitle)
                    .frame(minWidth: 108)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaveDisabled)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Save this prompt and select it.")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .overlay(Divider().opacity(0.5), alignment: .top)
    }

    private func deletePrompt() {
        guard let prompt = editingPrompt, canDeletePrompt else { return }
        onDelete?(prompt)
        dismissPanel()
    }

    private func save() -> CustomPrompt? {
        switch mode {
        case .add:
            return enhancementService.addPrompt(
                title: title,
                promptText: promptText,
                triggerWords: triggerWords,
                useSystemInstructions: useSystemInstructions
            )
        case .edit(let prompt):
            let updatedPrompt = CustomPrompt(
                id: prompt.id,
                title: title,
                promptText: promptText,
                triggerWords: triggerWords,
                useSystemInstructions: useSystemInstructions
            )
            enhancementService.updatePrompt(updatedPrompt)
            return updatedPrompt
        }
    }

    private var normalizedNewTriggerWord: String? {
        let trimmed = newTriggerWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !triggerWords.contains(where: { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) else {
            return nil
        }
        return trimmed
    }

    private func addTriggerWord() {
        guard let word = normalizedNewTriggerWord else { return }
        triggerWords.append(word)
        newTriggerWord = ""
    }
}

private struct TriggerWordChip: View {
    let word: String
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "mic.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(word)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 140, alignment: .leading)

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .help("Remove trigger word")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(AppCardBackground(cornerRadius: 7))
    }
}
