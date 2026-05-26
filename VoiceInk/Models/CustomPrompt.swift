import Foundation
import SwiftUI

typealias PromptIcon = String

struct CustomPrompt: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let promptText: String
    var isActive: Bool
    let icon: PromptIcon
    let description: String?
    let isPredefined: Bool
    let useSystemInstructions: Bool
    
    init(
        id: UUID = UUID(),
        title: String,
        promptText: String,
        isActive: Bool = false,
        icon: PromptIcon = "doc.text.fill",
        description: String? = nil,
        isPredefined: Bool = false,
        useSystemInstructions: Bool = true
    ) {
        self.id = id
        self.title = title
        self.promptText = promptText
        self.isActive = isActive
        self.icon = icon
        self.description = description
        self.isPredefined = isPredefined
        self.useSystemInstructions = useSystemInstructions
    }

    enum CodingKeys: String, CodingKey {
        case id, title, promptText, isActive, icon, description, isPredefined, useSystemInstructions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        promptText = try container.decode(String.self, forKey: .promptText)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        icon = try container.decode(PromptIcon.self, forKey: .icon)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        isPredefined = try container.decode(Bool.self, forKey: .isPredefined)
        useSystemInstructions = try container.decodeIfPresent(Bool.self, forKey: .useSystemInstructions) ?? true
    }
    
    var finalPromptText: String {
        if useSystemInstructions {
            return String(format: AIPrompts.customPromptTemplate, self.promptText)
        } else {
            return self.promptText
        }
    }
}

// MARK: - UI Extensions
extension CustomPrompt {
    func promptIcon(isSelected: Bool, onTap: @escaping () -> Void, onEdit: ((CustomPrompt) -> Void)? = nil, onDelete: ((CustomPrompt) -> Void)? = nil) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 30)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(NSColor.separatorColor), lineWidth: isSelected ? 0 : 0.5)
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
                
                if let onDelete = onDelete, !isPredefined {
                    Button(role: .destructive) {
                        let alert = NSAlert()
                        alert.messageText = "Delete Prompt?"
                        alert.informativeText = "Are you sure you want to delete '\(self.title)' prompt? This action cannot be undone."
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "Delete")
                        alert.addButton(withTitle: "Cancel")
                        
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
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
            )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}
