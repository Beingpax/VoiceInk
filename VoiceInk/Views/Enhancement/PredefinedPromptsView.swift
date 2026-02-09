import SwiftUI

struct PredefinedPromptsView: View {
    let onSelect: (TemplatePrompt) -> Void
    
    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 18), count: 2)
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(PromptTemplates.all, id: \.title) { template in
                    PredefinedTemplateButton(prompt: template) {
                        onSelect(template)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .frame(minWidth: 410, idealWidth: 520, maxWidth: 570, maxHeight: 440)
    }
}

struct PredefinedTemplateButton: View {
    let prompt: TemplatePrompt
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(NSColor.unemphasizedSelectedTextBackgroundColor))
                        .frame(width: 42, height: 42)
                        .overlay(
                            Image(systemName: prompt.icon)
                                .font(.system(size: 19, weight: .medium))
                                .foregroundColor(Color(NSColor.labelColor))
                        )
                    
                    Text(prompt.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Spacer(minLength: 0)
                }
                
                Text(prompt.description)
                    .font(.system(size: 12))
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(cardBackground)
            .overlay(cardStroke)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: cardShadowColor, radius: 6, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(NSColor.controlBackgroundColor))
    }
    
    private var cardStroke: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        Color(NSColor.separatorColor).opacity(0.35),
                        Color(NSColor.separatorColor).opacity(0.15)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    private var cardShadowColor: Color {
        Color(NSColor.shadowColor).opacity(0.25)
    }
}
