import SwiftUI

// Enhancement Prompt Popover for recorder views
struct EnhancementPromptPopover: View {
    @EnvironmentObject var enhancementService: AIEnhancementService
    @ObservedObject private var modeManager = ModeManager.shared
    @State private var selectedPrompt: CustomPrompt?

    private var currentMode: ModeConfig? {
        modeManager.currentEffectiveConfiguration
    }

    private var isEnhancementEnabled: Bool {
        currentMode?.isAIEnhancementEnabled == true
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Enhancement Toggle at the top
            HStack(spacing: 8) {
                Toggle("AI Enhancement", isOn: Binding(
                    get: { isEnhancementEnabled },
                    set: { newValue in
                        modeManager.updateCurrentEffectiveConfiguration { config in
                            config.isAIEnhancementEnabled = newValue
                            if newValue, config.selectedPrompt == nil {
                                config.selectedPrompt = enhancementService.allPrompts.first?.id.uuidString
                            }
                        }
                        refreshSelectedPrompt()
                    }
                ))
                    .foregroundColor(.white.opacity(0.9))
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    // Available Enhancement Prompts
                    ForEach(enhancementService.allPrompts) { prompt in
                        EnhancementPromptRow(
                            prompt: prompt,
                            isSelected: selectedPrompt?.id == prompt.id,
                            isDisabled: !isEnhancementEnabled,
                            action: {
                                modeManager.updateCurrentEffectiveConfiguration { config in
                                    config.isAIEnhancementEnabled = true
                                    config.selectedPrompt = prompt.id.uuidString
                                }
                                selectedPrompt = prompt
                            }
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
        .frame(width: 200)
        .frame(maxHeight: 340)
        .padding(.vertical, 8)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        .onAppear {
            refreshSelectedPrompt()
        }
        .onChange(of: modeManager.currentEffectiveConfiguration?.selectedPrompt) { _, _ in
            refreshSelectedPrompt()
        }
    }

    private func refreshSelectedPrompt() {
        guard let promptId = currentMode?.selectedPrompt.flatMap(UUID.init) else {
            selectedPrompt = nil
            return
        }
        selectedPrompt = enhancementService.allPrompts.first { $0.id == promptId }
    }
}

// Row view for each enhancement prompt in the popover
struct EnhancementPromptRow: View {
    let prompt: CustomPrompt
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(prompt.title)
                    .foregroundColor(isDisabled ? .white.opacity(0.4) : .white.opacity(0.9))
                    .font(.system(size: 13))
                    .lineLimit(1)

                if isSelected {
                    Spacer()
                    Image(systemName: "checkmark")
                        .foregroundColor(isDisabled ? AppTheme.Status.positive.opacity(0.70) : AppTheme.Status.positive)
                        .font(.system(size: 10))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.white.opacity(0.1) : Color.clear)
        .cornerRadius(4)
    }
}
