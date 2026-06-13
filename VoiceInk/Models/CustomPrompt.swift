import Foundation
import SwiftUI

struct CustomPrompt: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let promptText: String
    let triggerWords: [String]
    let useSystemInstructions: Bool
    
    init(
        id: UUID = UUID(),
        title: String,
        promptText: String,
        triggerWords: [String] = [],
        useSystemInstructions: Bool = true
    ) {
        self.id = id
        self.title = title
        self.promptText = promptText
        self.triggerWords = Self.normalizedTriggerWords(triggerWords)
        self.useSystemInstructions = useSystemInstructions
    }

    enum CodingKeys: String, CodingKey {
        case id, title, promptText, triggerWords, useSystemInstructions
        case legacyTriggerWord = "triggerWord"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        promptText = try container.decode(String.self, forKey: .promptText)
        let decodedTriggerWords = try container.decodeIfPresent([String].self, forKey: .triggerWords)
        let legacyTriggerWord = try container.decodeIfPresent(String.self, forKey: .legacyTriggerWord)
        triggerWords = Self.normalizedTriggerWords(
            decodedTriggerWords ?? legacyTriggerWord.map { [$0] } ?? []
        )
        useSystemInstructions = try container.decodeIfPresent(Bool.self, forKey: .useSystemInstructions) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(promptText, forKey: .promptText)
        if !triggerWords.isEmpty {
            try container.encode(triggerWords, forKey: .triggerWords)
        }
        try container.encode(useSystemInstructions, forKey: .useSystemInstructions)
    }

    private static func normalizedTriggerWords(_ words: [String]) -> [String] {
        var seen = Set<String>()
        return words.compactMap { word in
            let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return trimmed
        }
    }
    
    var finalPromptText: String {
        if useSystemInstructions {
            return String(format: AIPrompts.enhancementSystemTemplate, self.promptText)
        } else {
            return self.promptText
        }
    }
}

// MARK: - UI Extensions
extension CustomPrompt {
    func promptIcon(isSelected: Bool, onTap: @escaping () -> Void, onEdit: ((CustomPrompt) -> Void)? = nil, onDelete: ((CustomPrompt) -> Void)? = nil) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)

            if !triggerWords.isEmpty {
                Image(systemName: "mic.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .accessibilityLabel("Has trigger words")
            }
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
                        alert.informativeText = String(format: String(localized: "Are you sure you want to delete '%@' prompt? This action cannot be undone."), self.title)
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
