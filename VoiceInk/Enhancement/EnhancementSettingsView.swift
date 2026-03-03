import SwiftUI
import UniformTypeIdentifiers

struct EnhancementSettingsView: View {
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @State private var isEditingPrompt = false
    @State private var isShortcutsExpanded = false
    @State private var selectedPromptForEdit: CustomPrompt?
    
    private var isPanelOpen: Bool {
        isEditingPrompt || selectedPromptForEdit != nil
    }
    
    private func closePanel() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
            isEditingPrompt = false
            selectedPromptForEdit = nil
        }
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            Form {
                Section {
                    Toggle(isOn: $enhancementService.isEnhancementEnabled) {
                        HStack(spacing: 4) {
                            Text("Enable Enhancement")
                            InfoTip(
                                "AI enhancement lets you pass the transcribed audio through LLMs to post-process using different prompts suitable for different use cases like e-mails, summary, writing, etc.",
                                learnMoreURL: "https://tryvoiceink.com/docs/enhancements-configuring-models"
                            )
                        }
                    }
                    .toggleStyle(.switch)
                    
                    HStack(spacing: 24) {
                        Toggle(isOn: $enhancementService.useClipboardContext) {
                            HStack(spacing: 4) {
                                Text("Clipboard Context")
                                InfoTip("Use clipboard text to understand context for better enhancement.")
                            }
                        }
                        .toggleStyle(.switch)

                        Toggle(isOn: $enhancementService.useScreenCaptureContext) {
                            HStack(spacing: 4) {
                                Text("Screen Context")
                                InfoTip("Capture on-screen text to understand context for better enhancement.")
                            }
                        }
                        .toggleStyle(.switch)
                    }
                    .opacity(enhancementService.isEnhancementEnabled ? 1.0 : 0.8)
                } header: {
                    Text("General")
                }
                
                APIKeyManagementView()
                    .opacity(enhancementService.isEnhancementEnabled ? 1.0 : 0.8)
                
                Section {
                    ReorderablePromptGrid(
                        selectedPromptId: enhancementService.selectedPromptId,
                        onPromptSelected: { prompt in
                            enhancementService.setActivePrompt(prompt)
                        },
                        onEditPrompt: { prompt in
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                                selectedPromptForEdit = prompt
                            }
                        },
                        onDeletePrompt: { prompt in
                            enhancementService.deletePrompt(prompt)
                        }
                    )
                    .padding(.vertical, 8)
                } header: {
                    HStack {
                        Text("Enhancement Prompts")
                        Spacer()
                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                                isEditingPrompt = true
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Add new prompt")
                    }
                }
                .opacity(enhancementService.isEnhancementEnabled ? 1.0 : 0.8)
                
                Section {
                    DisclosureGroup(isExpanded: $isShortcutsExpanded) {
                        EnhancementShortcutsView()
                            .padding(.vertical, 8)
                    } label: {
                        HStack {
                            Text("Shortcuts")
                            .font(.headline)
                            .foregroundColor(.primary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation {
                                isShortcutsExpanded.toggle()
                            }
                        }
                    }
                }
                .opacity(enhancementService.isEnhancementEnabled ? 1.0 : 0.8)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color(NSColor.controlBackgroundColor))
            .disabled(isPanelOpen)
            .blur(radius: isPanelOpen ? 2 : 0)
            .animation(.spring(response: 0.4, dampingFraction: 0.9), value: isPanelOpen)
            
            if isPanelOpen {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .onTapGesture {
                        closePanel()
                    }
                    .transition(.opacity)
                    .zIndex(1)
            }
            
            if isPanelOpen {
                HStack(spacing: 0) {
                    Spacer()
                    
                    Group {
                        if let prompt = selectedPromptForEdit {
                            PromptEditorView(mode: .edit(prompt)) {
                                closePanel()
                            }
                        } else if isEditingPrompt {
                            PromptEditorView(mode: .add) {
                                closePanel()
                            }
                        }
                    }
                    .frame(width: 450)
                    .frame(maxHeight: .infinity)
                    .background(
                        Color(NSColor.windowBackgroundColor)
                    )
                    .overlay(
                        Divider(), alignment: .leading
                    )
                    .shadow(color: .black.opacity(0.15), radius: 12, x: -4, y: 0)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                .ignoresSafeArea()
                .zIndex(2)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

// MARK: - Reorderable Grid
private struct ReorderablePromptGrid: View {
    @EnvironmentObject private var enhancementService: AIEnhancementService
    
    let selectedPromptId: UUID?
    let onPromptSelected: (CustomPrompt) -> Void
    let onEditPrompt: ((CustomPrompt) -> Void)?
    let onDeletePrompt: ((CustomPrompt) -> Void)?
    
    @State private var draggingItem: CustomPrompt?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if enhancementService.customPrompts.isEmpty {
                Text("No prompts available")
                    .foregroundColor(.secondary)
                    .font(.caption)
            } else {
                let columns = [
                    GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 36)
                ]
                
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(enhancementService.customPrompts) { prompt in
                        prompt.promptIcon(
                            isSelected: selectedPromptId == prompt.id,
                            onTap: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    onPromptSelected(prompt)
                                }
                            },
                            onEdit: onEditPrompt,
                            onDelete: onDeletePrompt
                        )
                        .opacity(draggingItem?.id == prompt.id ? 0.3 : 1.0)
                        .scaleEffect(draggingItem?.id == prompt.id ? 1.05 : 1.0)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(
                                    draggingItem != nil && draggingItem?.id != prompt.id
                                    ? Color.accentColor.opacity(0.25)
                                    : Color.clear,
                                    lineWidth: 1
                                )
                        )
                        .animation(.easeInOut(duration: 0.15), value: draggingItem?.id == prompt.id)
                        .onDrag {
                            draggingItem = prompt
                            return NSItemProvider(object: prompt.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: PromptDropDelegate(
                                item: prompt,
                                prompts: $enhancementService.customPrompts,
                                draggingItem: $draggingItem
                            )
                        )
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                
                HStack {
                    Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    
                    Text("Double-click to edit • Right-click for more options")
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.top, 8)
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Drop Delegate
private struct PromptDropDelegate: DropDelegate {
    let item: CustomPrompt
    @Binding var prompts: [CustomPrompt]
    @Binding var draggingItem: CustomPrompt?
    
    func dropEntered(info: DropInfo) {
        guard let draggingItem = draggingItem, draggingItem != item else { return }
        guard let fromIndex = prompts.firstIndex(of: draggingItem),
              let toIndex = prompts.firstIndex(of: item) else { return }
        
        if prompts[toIndex].id != draggingItem.id {
            withAnimation(.easeInOut(duration: 0.12)) {
                let from = fromIndex
                let to = toIndex
                prompts.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            }
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        draggingItem = nil
        return true
    }
}
