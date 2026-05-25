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
    @State private var selectedIcon: PromptIcon
    @State private var description: String
    @State private var triggerWords: [String]
    @State private var useSystemInstructions: Bool
    @State private var showingIconPicker = false
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
            _selectedIcon = State(initialValue: "doc.text.fill")
            _description = State(initialValue: "")
            _triggerWords = State(initialValue: [])
            _useSystemInstructions = State(initialValue: true)
        case .edit(let prompt):
            _title = State(initialValue: prompt.title)
            _promptText = State(initialValue: prompt.promptText)
            _selectedIcon = State(initialValue: prompt.icon)
            _description = State(initialValue: prompt.description ?? "")
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
                    if !isEditingPredefinedPrompt {
                        topControls
                    }

                    identitySection

                    if !isEditingPredefinedPrompt {
                        instructionsEditor
                    }

                    triggerWordsEditor
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

    private var topControls: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $useSystemInstructions) {
                HStack(spacing: 4) {
                    Text("Use System Template")
                    InfoTip("If enabled, your instructions are combined with a general-purpose template to improve transcription quality.\n\nDisable for full control over the AI's system prompt (for advanced users).")
                }
            }
            .toggleStyle(.switch)

            Spacer(minLength: 12)

            if case .add = mode {
                templateMenu
            }
        }
    }

    private var templateMenu: some View {
        Menu {
            ForEach(PromptTemplates.all, id: \.title) { template in
                Button {
                    title = template.title
                    promptText = template.promptText
                    selectedIcon = template.icon
                    description = template.description
                } label: {
                    Label(template.title, systemImage: template.icon)
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
        HStack(alignment: .center, spacing: 14) {
            if isEditingPredefinedPrompt {
                promptIconPreview
            } else {
                Button(action: { showingIconPicker = true }) {
                    promptIconPreview
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingIconPicker, arrowEdge: .bottom) {
                    IconPickerPopover(selectedIcon: $selectedIcon, isPresented: $showingIconPicker)
                }
                .help("Choose icon")
            }

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

    private var promptIconPreview: some View {
        Image(systemName: selectedIcon)
            .font(.system(size: 22, weight: .medium))
            .foregroundColor(.primary)
            .frame(width: 52, height: 52)
            .background(GroupedCardBackground(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
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

    private var triggerWordsEditor: some View {
        TriggerWordsEditor(triggerWords: $triggerWords)
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
                icon: selectedIcon,
                description: description.isEmpty ? nil : description,
                triggerWords: triggerWords,
                useSystemInstructions: useSystemInstructions
            )
        case .edit(let prompt):
            let updatedPrompt = CustomPrompt(
                id: prompt.id,
                title: prompt.isPredefined ? prompt.title : title,
                promptText: prompt.isPredefined ? prompt.promptText : promptText,
                isActive: prompt.isActive,
                icon: prompt.isPredefined ? prompt.icon : selectedIcon,
                description: prompt.isPredefined ? prompt.description : (description.isEmpty ? nil : description),
                isPredefined: prompt.isPredefined,
                triggerWords: triggerWords,
                useSystemInstructions: useSystemInstructions
            )
            enhancementService.updatePrompt(updatedPrompt)
            return updatedPrompt
        }
    }
}

// MARK: - Trigger Words Editor
struct TriggerWordsEditor: View {
    @Binding var triggerWords: [String]
    @State private var newTriggerWord: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Add trigger word", text: $newTriggerWord)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(GroupedCardBackground(cornerRadius: 7))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .onSubmit { addTriggerWord() }

                Button(action: { addTriggerWord() }) {
                    Image(systemName: "plus.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .disabled(newTriggerWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !triggerWords.isEmpty {
                TagLayout(alignment: .leading, spacing: 6) {
                    ForEach(triggerWords, id: \.self) { word in
                        TriggerWordItemView(word: word) {
                            triggerWords.removeAll { $0 == word }
                        }
                    }
                }
            }
        }
    }
    
    private func addTriggerWord() {
        let trimmedWord = newTriggerWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWord.isEmpty else { return }
        
        let lowerCaseWord = trimmedWord.lowercased()
        guard !triggerWords.contains(where: { $0.lowercased() == lowerCaseWord }) else { return }
        
        triggerWords.append(trimmedWord)
        newTriggerWord = ""
    }
}

// MARK: - Trigger Word Item
struct TriggerWordItemView: View {
    let word: String
    let onDelete: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 4) {
                Text(word)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 120, alignment: .leading)
                    .foregroundColor(.primary)
            
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(GroupedCardBackground(cornerRadius: 4))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Tag Layout
struct TagLayout: Layout {
    var alignment: Alignment = .leading
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var height: CGFloat = 0
        var currentRowWidth: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentRowWidth + size.width > maxWidth {
                // New row
                height += size.height + spacing
                currentRowWidth = size.width + spacing
            } else {
                // Same row
                currentRowWidth += size.width + spacing
            }
            
            if height == 0 {
                height = size.height
            }
        }
        
        return CGSize(width: maxWidth, height: height)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        let maxHeight = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += maxHeight + spacing
            }
            
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
        }
    }
}

// MARK: - Icon Picker
struct IconPickerPopover: View {
    @Binding var selectedIcon: PromptIcon
    @Binding var isPresented: Bool
    
    var body: some View {
        let columns = [
            GridItem(.adaptive(minimum: 45, maximum: 52), spacing: 14)
        ]
        
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(PromptIcon.allCases, id: \.self) { icon in
                    Button(action: {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                            selectedIcon = icon
                            isPresented = false
                        }
                    }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedIcon == icon ? Color(NSColor.windowBackgroundColor) : Color(NSColor.controlBackgroundColor))
                                .frame(width: 52, height: 52)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(selectedIcon == icon ? Color(NSColor.separatorColor) : Color.secondary.opacity(0.2), lineWidth: selectedIcon == icon ? 2 : 1)
                                )
                            
                            Image(systemName: icon)
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(.primary)
                        }
                        .scaleEffect(selectedIcon == icon ? 1.1 : 1.0)
                        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: selectedIcon == icon)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .frame(width: 400, height: 400)
    }
}
