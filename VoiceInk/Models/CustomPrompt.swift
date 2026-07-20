import Foundation
import SwiftUI

struct CustomPrompt: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let promptText: String
    let useSystemInstructions: Bool

    init(
        id: UUID = UUID(),
        title: String,
        promptText: String,
        useSystemInstructions: Bool = true
    ) {
        self.id = id
        self.title = title
        self.promptText = promptText
        self.useSystemInstructions = useSystemInstructions
    }

    enum CodingKeys: String, CodingKey {
        case id, title, promptText, useSystemInstructions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        promptText = try container.decode(String.self, forKey: .promptText)
        useSystemInstructions = try container.decodeIfPresent(Bool.self, forKey: .useSystemInstructions) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(promptText, forKey: .promptText)
        try container.encode(useSystemInstructions, forKey: .useSystemInstructions)
    }

    var finalPromptText: String {
        finalPromptText(for: nil)
    }

    // Apple Intelligence gets a compact template (AIPrompts.appleIntelligenceEnhancementSystemTemplate)
    // instead of the full multi-section one — the on-device model loses track of instructions in
    // the longer prompt and either echoes the scaffolding back or answers the dictation as a
    // chat message. See that constant's doc comment for the measured evidence. Prompts with
    // useSystemInstructions == false (e.g. Rewrite, Assistant) are already complete,
    // provider-agnostic instructions and are returned as-is regardless of provider.
    func finalPromptText(for provider: AIProvider?) -> String {
        guard useSystemInstructions else { return self.promptText }

        let template =
            provider == .appleIntelligence
            ? AIPrompts.appleIntelligenceEnhancementSystemTemplate
            : AIPrompts.enhancementSystemTemplate
        return String(format: template, self.promptText)
    }
}

// MARK: - UI Extensions
extension CustomPrompt {
    func promptIcon(
        isSelected: Bool, onTap: @escaping () -> Void, onEdit: ((CustomPrompt) -> Void)? = nil,
        onDelete: ((CustomPrompt) -> Void)? = nil
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .frame(maxWidth: .infinity, minHeight: 30)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? AppTheme.Accent.primary : AppTheme.Surface.control)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(AppTheme.Border.control, lineWidth: isSelected ? 0 : 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if let onEdit = onEdit {
                onEdit(self)
            }
        }
        .onTapGesture(count: 1) {
            onTap()
        }
        .contextMenu {
            if onEdit != nil || onDelete != nil {
                if let onEdit = onEdit {
                    Button {
                        onEdit(self)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                }

                if let onDelete = onDelete {
                    Button(role: .destructive) {
                        let alert = NSAlert()
                        alert.messageText = String(localized: "Delete Prompt?")
                        alert.informativeText = String(
                            format: String(
                                localized: "Are you sure you want to delete '%@' prompt? This action cannot be undone."),
                            self.title)
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: String(localized: "Delete"))
                        alert.addButton(withTitle: String(localized: "Cancel"))

                        let response = alert.runModal()
                        if response == .alertFirstButtonReturn {
                            onDelete(self)
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    static func addNewButton(action: @escaping () -> Void) -> some View {
        Label("Add New", systemImage: "plus.circle.fill")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 30)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(AppTheme.Surface.control)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(AppTheme.Border.control, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }
}
