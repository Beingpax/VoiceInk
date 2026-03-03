import SwiftUI

// Enhancement Prompt Popover for recorder views
struct EnhancementPromptPopover: View {
    @EnvironmentObject var enhancementService: AIEnhancementService
    @State private var selectedPrompt: CustomPrompt?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Enhancement Toggle at the top
            HStack(spacing: 8) {
                Toggle("AI Enhancement", isOn: $enhancementService.isEnhancementEnabled)
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
                            isDisabled: !enhancementService.isEnhancementEnabled,
                            action: {
                                // If enhancement is disabled, enable it first
                                if !enhancementService.isEnhancementEnabled {
                                    enhancementService.isEnhancementEnabled = true
                                }
                                enhancementService.setActivePrompt(prompt)
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
            // Set the initially selected prompt
            selectedPrompt = enhancementService.activePrompt
        }
        .onChange(of: enhancementService.selectedPromptId) { oldValue, newValue in
            selectedPrompt = enhancementService.activePrompt
        }
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
                // Use the icon from the prompt
                Image(systemName: prompt.icon)
                    .font(.system(size: 14))
                    .foregroundColor(isDisabled ? .white.opacity(0.4) : .white.opacity(0.7))

                Text(prompt.title)
                    .foregroundColor(isDisabled ? .white.opacity(0.4) : .white.opacity(0.9))
                    .font(.system(size: 13))
                    .lineLimit(1)

                if isSelected {
                    Spacer()
                    Image(systemName: "checkmark")
                        .foregroundColor(isDisabled ? .green.opacity(0.7) : .green)
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