import SwiftUI
import UniformTypeIdentifiers

struct EnhancementSettingsView: View {
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @State private var isEditingPrompt = false
    @State private var isShowingSettings = false
    @State private var selectedPromptForEdit: CustomPrompt?
    @State private var panelID = UUID()

    private let panelWidth: CGFloat = 400

    private enum PanelType {
        case promptEditor
        case settings
    }

    private var activePanel: PanelType? {
        if isShowingSettings { return .settings }
        if isEditingPrompt || selectedPromptForEdit != nil { return .promptEditor }
        return nil
    }

    private var isPanelOpen: Bool {
        activePanel != nil
    }

    private func openPromptPanel() {
        isShowingSettings = false
        panelID = UUID()
    }

    private func closePanel() {
        withAnimation(.smooth(duration: 0.3)) {
            isEditingPrompt = false
            selectedPromptForEdit = nil
            isShowingSettings = false
        }
    }

    @State private var noiseReduction = true
    @State private var clarityBoost = true
    @State private var detailPreservation = false
    @State private var noiseLevel: Double = 0.8
    @State private var clarityLevel: Double = 0.9
    @State private var detailLevel: Double = 0.4

    var body: some View {
        VStack(spacing: 0) {
            // Premium Header with Centered Wave Graphic
            VStack(spacing: 12) {
                // Subtle neon glowing waves decoration
                HStack(spacing: 4) {
                    ForEach(0..<15) { idx in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(LinearGradient(
                                colors: [Color(red: 0.54, green: 0.12, blue: 0.92), Color(red: 0.28, green: 0.58, blue: 0.95)],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                            .frame(width: 3, height: CGFloat.random(in: 6...24))
                            .opacity(0.5)
                    }
                }
                .frame(height: 30)
                .padding(.top, 12)

                Text("Enhancement Settings")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                
                Text("Post-process and polish transcribed audio using advanced AI models")
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 20)
            .background(Color(red: 0.97, green: 0.97, blue: 0.98))

            Form {
                // Enable Enhancement Block
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.1))
                                    .frame(width: 32, height: 32)
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color(red: 0.36, green: 0.28, blue: 0.88))
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AI Audio Enhancement")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                                Text("Automatically post-process transcriptions using large language models")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.5))
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: $enhancementService.isEnhancementEnabled)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // AI Provider Integration Block
                Section {
                    APIKeyManagementView()
                        .opacity(enhancementService.isEnhancementEnabled ? 1.0 : 0.8)
                } header: {
                    HStack {
                        Text("AI Provider Integration")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.4))
                        Spacer()
                        if enhancementService.isEnhancementEnabled {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                                Text("Active")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.green)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(4)
                        }
                    }
                }

                // Enhancement Prompts Section
                Section {
                    ReorderablePromptGrid(
                        selectedPromptId: enhancementService.selectedPromptId,
                        onPromptSelected: { prompt in
                            enhancementService.setActivePrompt(prompt)
                        },
                        onEditPrompt: { prompt in
                            openPromptPanel()
                            withAnimation(.smooth(duration: 0.3)) {
                                selectedPromptForEdit = prompt
                            }
                        },
                        onDeletePrompt: { prompt in
                            enhancementService.deletePrompt(prompt)
                        }
                    )
                    .padding(.vertical, 4)
                    .opacity(enhancementService.isEnhancementEnabled ? 1.0 : 0.5)
                    .disabled(!enhancementService.isEnhancementEnabled)
                } header: {
                    HStack {
                        Text("Enhancement Prompts")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.4))
                        Spacer()
                        Button {
                            openPromptPanel()
                            withAnimation(.smooth(duration: 0.3)) {
                                isEditingPrompt = true
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                Text("New Prompt")
                            }
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(red: 0.36, green: 0.28, blue: 0.88))
                        }
                        .buttonStyle(.plain)
                        .disabled(!enhancementService.isEnhancementEnabled)
                    }
                }

                // Enhancement Behavior Section (Mockup 1 Details)
                Section {
                    HStack(spacing: 16) {
                        // Noise Reduction Card
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "waveform.badge.minus")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(noiseReduction ? Color(red: 0.36, green: 0.28, blue: 0.88) : .secondary)
                                Text("Noise Reduction")
                                    .font(.system(size: 12, weight: .bold))
                                Spacer()
                                Toggle("", isOn: $noiseReduction)
                                    .toggleStyle(.switch)
                                    .controlSize(.mini)
                            }
                            
                            // Micro-dotted intensity bar
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 3) {
                                    ForEach(0..<10) { idx in
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(idx < Int(noiseLevel * 10) && noiseReduction ? Color(red: 0.36, green: 0.28, blue: 0.88) : Color.primary.opacity(0.1))
                                            .frame(width: 4, height: 8)
                                    }
                                    Spacer()
                                    Text("\(Int(noiseLevel * 100))%")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(12)
                        .background(Color.white)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                        )
                        
                        // Clarity Boost Card
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "music.note.list")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(clarityBoost ? Color(red: 0.54, green: 0.12, blue: 0.92) : .secondary)
                                Text("Clarity Boost")
                                    .font(.system(size: 12, weight: .bold))
                                Spacer()
                                Toggle("", isOn: $clarityBoost)
                                    .toggleStyle(.switch)
                                    .controlSize(.mini)
                            }
                            
                            // Micro-dotted intensity bar
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 3) {
                                    ForEach(0..<10) { idx in
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(idx < Int(clarityLevel * 10) && clarityBoost ? Color(red: 0.54, green: 0.12, blue: 0.92) : Color.primary.opacity(0.1))
                                            .frame(width: 4, height: 8)
                                    }
                                    Spacer()
                                    Text("\(Int(clarityLevel * 100))%")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(12)
                        .background(Color.white)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                        )
                        
                        // Detail Preservation Card
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(detailPreservation ? Color(red: 0.28, green: 0.58, blue: 0.95) : .secondary)
                                Text("Detail Preserve")
                                    .font(.system(size: 12, weight: .bold))
                                Spacer()
                                Toggle("", isOn: $detailPreservation)
                                    .toggleStyle(.switch)
                                    .controlSize(.mini)
                            }
                            
                            // Micro-dotted intensity bar
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 3) {
                                    ForEach(0..<10) { idx in
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(idx < Int(detailLevel * 10) && detailPreservation ? Color(red: 0.28, green: 0.58, blue: 0.95) : Color.primary.opacity(0.1))
                                            .frame(width: 4, height: 8)
                                    }
                                    Spacer()
                                    Text("\(Int(detailLevel * 100))%")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(12)
                        .background(Color.white)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                        )
                    }
                    .padding(.vertical, 4)
                    .opacity(enhancementService.isEnhancementEnabled ? 1.0 : 0.5)
                    .disabled(!enhancementService.isEnhancementEnabled)
                } header: {
                    Text("Enhancement Behavior")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.4))
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.97, green: 0.97, blue: 0.98))
        }
        .slidingPanel(isPresented: .init(
            get: { isPanelOpen },
            set: { newValue in
                if !newValue { closePanel() }
            }
        ), width: panelWidth) {
            Group {
                switch activePanel {
                case .settings:
                    EnhancementSettingsPanel(onDismiss: closePanel)
                case .promptEditor:
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
                    .id(panelID)
                case nil:
                    EmptyView()
                }
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
