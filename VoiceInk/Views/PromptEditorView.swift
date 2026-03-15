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
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var enhancementService: AIEnhancementService
    var onDismiss: (() -> Void)?
    @State private var title: String
    @State private var promptText: String
    @State private var selectedIcon: PromptIcon
    @State private var description: String
    @State private var triggerWords: [String]
    @State private var useSystemInstructions: Bool
    @State private var showingIconPicker = false
    
    private var isEditingPredefinedPrompt: Bool {
        if case .edit(let prompt) = mode {
            return prompt.isPredefined
        }
        return false
    }
    
    init(mode: Mode, onDismiss: (() -> Void)? = nil) {
        self.mode = mode
        self.onDismiss = onDismiss
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
        if let onDismiss = onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Text(isEditingPredefinedPrompt ? "Edit Trigger Words" : (mode == .add ? "New Prompt" : "Edit Prompt"))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: dismissPanel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(
                Divider().opacity(0.5), alignment: .bottom
            )

            // Content
            if isEditingPredefinedPrompt {
                predefinedPromptForm
            } else {
                customPromptForm
            }

            // Footer
            VStack(spacing: 0) {
                HStack {
                    Button("Cancel") { dismissPanel() }
                        .keyboardShortcut(.escape, modifiers: [])
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button {
                        save()
                        dismissPanel()
                    } label: {
                        Text("Save Changes")
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isEditingPredefinedPrompt ? false : (title.isEmpty || promptText.isEmpty))
                    .keyboardShortcut(.return, modifiers: .command)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Predefined Prompt Form

    private var predefinedPromptForm: some View {
        Form {
            Section {
                Text("You can only customize the trigger words for system prompts.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } header: {
                Text("Editing: \(title)")
            }

            Section {
                TriggerWordsEditor(triggerWords: $triggerWords)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Custom Prompt Form

    private var customPromptForm: some View {
        Form {
            Section {
                HStack(alignment: .center, spacing: 14) {
                    Button(action: { showingIconPicker = true }) {
                        Image(systemName: selectedIcon)
                            .font(.system(size: 22))
                            .foregroundColor(.primary)
                            .frame(width: 44, height: 44)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingIconPicker, arrowEdge: .bottom) {
                        IconPickerPopover(selectedIcon: $selectedIcon, isPresented: $showingIconPicker)
                    }

                    TextField("Prompt Name", text: $title)
                        .textFieldStyle(.roundedBorder)
                }

                TextField("Brief description", text: $description)
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text("Details")
            }

            Section {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $promptText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 160)
                        .scrollContentBackground(.hidden)

                    if promptText.isEmpty {
                        Text("Enter your custom prompt instructions here...")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }

                Toggle(isOn: $useSystemInstructions) {
                    HStack(spacing: 4) {
                        Text("Use System Template")
                        InfoTip("If enabled, your instructions are combined with a general-purpose template to improve transcription quality.\n\nDisable for full control over the AI's system prompt (for advanced users).")
                    }
                }
                .toggleStyle(.switch)
            } header: {
                Text("Instructions")
            }

            Section {
                TriggerWordsEditor(triggerWords: $triggerWords)
            } header: {
                HStack(spacing: 4) {
                    Text("Trigger Words")
                    InfoTip("Add words that automatically activate this prompt. For example, 'summarize', 'email', 'translate'.")
                }
            }

            if case .add = mode {
                Section {
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
                        Label("Start with Template", systemImage: "sparkles")
                    }
                    .menuStyle(.borderlessButton)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func save() {
        switch mode {
        case .add:
            enhancementService.addPrompt(
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
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addTriggerWord() }

                Button(action: { addTriggerWord() }) {
                    Image(systemName: "plus.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
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
            } else {
                Text("No trigger words added")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
                    .italic()
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
        .background(Color(NSColor.controlBackgroundColor))
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
