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
    @State private var description: String
    @State private var useSystemInstructions: Bool
    @State private var showDeleteConfirmation = false
    
    private var isEditingPredefinedPrompt: Bool {
        if case .edit(let prompt) = mode {
            return prompt.isPredefined
        }
        return false
    }

    private var saveButtonTitle: String {
        mode == .add ? "Create & Select" : "Save & Select"
    }

    private var panelTitle: String {
        mode == .add ? "New Prompt" : "Edit Prompt"
    }

    private var promptKindLabel: String {
        if isEditingPredefinedPrompt {
            return "System prompt"
        }
        return "Custom prompt"
    }

    private var editingPrompt: CustomPrompt? {
        if case .edit(let prompt) = mode {
            return prompt
        }
        return nil
    }

    private var canDeletePrompt: Bool {
        guard let prompt = editingPrompt else { return false }
        return !prompt.isPredefined && onDelete != nil
    }

    private var isSaveDisabled: Bool {
        if isEditingPredefinedPrompt { return false }
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
            _description = State(initialValue: "")
            _useSystemInstructions = State(initialValue: true)
        case .edit(let prompt):
            _title = State(initialValue: prompt.title)
            _promptText = State(initialValue: prompt.promptText)
            _description = State(initialValue: prompt.description ?? "")
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
                    identitySection

                    if case .add = mode {
                        templateMenu
                    }

                    if !isEditingPredefinedPrompt {
                        instructionsEditor
                        systemTemplateToggle
                    }
                }
                .padding(20)
            }
            .background(Color(NSColor.controlBackgroundColor))

            footer
        }
        .background(Color(NSColor.windowBackgroundColor))
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
            Text("Are you sure you want to delete '\(title)'? This action cannot be undone.")
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
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .help("Back")

            VStack(alignment: .leading, spacing: 2) {
                Text(panelTitle)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text(promptKindLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(NSColor.windowBackgroundColor))
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
            ForEach(PromptTemplates.all, id: \.title) { template in
                Button {
                    title = template.title
                    promptText = template.promptText
                    description = template.description
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

    private var identitySection: some View {
        Group {
            if isEditingPredefinedPrompt {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("Prompt name", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(GroupedCardBackground(cornerRadius: 7))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
        }
    }

    private var instructionsEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $promptText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 220)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(GroupedCardBackground(cornerRadius: 8))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            if promptText.isEmpty {
                Text("Write prompt instructions")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
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
                .tint(Color(NSColor.systemRed))
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
        .background(Color(NSColor.windowBackgroundColor))
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
                description: description.isEmpty ? nil : description,
                useSystemInstructions: useSystemInstructions
            )
        case .edit(let prompt):
            let updatedPrompt = CustomPrompt(
                id: prompt.id,
                title: prompt.isPredefined ? prompt.title : title,
                promptText: prompt.isPredefined ? prompt.promptText : promptText,
                isActive: prompt.isActive,
                icon: prompt.icon,
                description: prompt.isPredefined ? prompt.description : (description.isEmpty ? nil : description),
                isPredefined: prompt.isPredefined,
                useSystemInstructions: useSystemInstructions
            )
            enhancementService.updatePrompt(updatedPrompt)
            return updatedPrompt
        }
    }
}
