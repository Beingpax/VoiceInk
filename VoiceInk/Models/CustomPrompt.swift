import Foundation
import SwiftUI

enum PromptIcon: String, Codable, CaseIterable {
    // Document & Text
    case documentFill = "doc.text.fill"
    case textbox = "textbox"
    case sealedFill = "checkmark.seal.fill"
    
    // Communication
    case chatFill = "bubble.left.and.bubble.right.fill"
    case messageFill = "message.fill"
    case emailFill = "envelope.fill"
    
    // Professional
    case meetingFill = "person.2.fill"
    case presentationFill = "person.wave.2.fill"
    case briefcaseFill = "briefcase.fill"
    
    // Technical
    case codeFill = "curlybraces"
    case terminalFill = "terminal.fill"
    case gearFill = "gearshape.fill"
    
    // Content
    case blogFill = "doc.text.image.fill"
    case notesFill = "note"
    case bookFill = "book.fill"
    case bookmarkFill = "bookmark.fill"
    case pencilFill = "pencil.circle.fill"
    
    // Media & Creative
    case videoFill = "video.fill"
    case micFill = "mic.fill"
    case musicFill = "music.note"
    case photoFill = "photo.fill"
    case brushFill = "paintbrush.fill"
    
    var title: String {
        switch self {
        // Document & Text
        case .documentFill: return "Document"
        case .textbox: return "Textbox"
        case .sealedFill: return "Sealed"
            
        // Communication
        case .chatFill: return "Chat"
        case .messageFill: return "Message"
        case .emailFill: return "Email"
            
        // Professional
        case .meetingFill: return "Meeting"
        case .presentationFill: return "Presentation"
        case .briefcaseFill: return "Briefcase"
            
        // Technical
        case .codeFill: return "Code"
        case .terminalFill: return "Terminal"
        case .gearFill: return "Settings"
            
        // Content
        case .blogFill: return "Blog"
        case .notesFill: return "Notes"
        case .bookFill: return "Book"
        case .bookmarkFill: return "Bookmark"
        case .pencilFill: return "Edit"
            
        // Media & Creative
        case .videoFill: return "Video"
        case .micFill: return "Audio"
        case .musicFill: return "Music"
        case .photoFill: return "Photo"
        case .brushFill: return "Design"
        }
    }
}

struct CustomPrompt: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let promptText: String
    var isActive: Bool
    let icon: PromptIcon
    let description: String?
    let isPredefined: Bool
    let triggerWords: [String]
    
    init(
        id: UUID = UUID(),
        title: String,
        promptText: String,
        isActive: Bool = false,
        icon: PromptIcon = .documentFill,
        description: String? = nil,
        isPredefined: Bool = false,
        triggerWords: [String] = []
    ) {
        self.id = id
        self.title = title
        self.promptText = promptText
        self.isActive = isActive
        self.icon = icon
        self.description = description
        self.isPredefined = isPredefined
        self.triggerWords = triggerWords
    }
}

// MARK: - UI Extensions
extension CustomPrompt {
    func promptIcon(isSelected: Bool, shortcutIndex: Int? = nil, onTap: @escaping () -> Void, onEdit: ((CustomPrompt) -> Void)? = nil, onDelete: ((CustomPrompt) -> Void)? = nil) -> some View {
        VStack(spacing: 4) {
            ZStack {
                // Dynamic background with blur effect
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            gradient: isSelected ?
                                Gradient(colors: [
                                    Color.accentColor.opacity(0.9),
                                    Color.accentColor.opacity(0.7)
                                ]) :
                                Gradient(colors: [
                                    Color(NSColor.controlBackgroundColor).opacity(0.95),
                                    Color(NSColor.controlBackgroundColor).opacity(0.85)
                                ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        isSelected ?
                                            Color.white.opacity(0.3) : Color.white.opacity(0.15),
                                        isSelected ?
                                            Color.white.opacity(0.1) : Color.white.opacity(0.05)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(
                        color: isSelected ?
                            Color.accentColor.opacity(0.4) : Color.black.opacity(0.1),
                        radius: isSelected ? 10 : 6,
                        x: 0,
                        y: 3
                    )
                
                // Decorative background elements
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                isSelected ?
                                    Color.white.opacity(0.15) : Color.white.opacity(0.08),
                                Color.clear
                            ]),
                            center: .center,
                            startRadius: 1,
                            endRadius: 25
                        )
                    )
                    .frame(width: 50, height: 50)
                    .offset(x: -15, y: -15)
                    .blur(radius: 2)
                
                // Icon with enhanced effects
                Image(systemName: icon.rawValue)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: isSelected ?
                                [Color.white, Color.white.opacity(0.9)] :
                                [Color.primary.opacity(0.9), Color.primary.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(
                        color: isSelected ?
                            Color.white.opacity(0.5) : Color.clear,
                        radius: 4
                    )
                    .shadow(
                        color: isSelected ?
                            Color.accentColor.opacity(0.5) : Color.clear,
                        radius: 3
                    )
            }
            .frame(width: 48, height: 48)
            
            // Enhanced title styling
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ?
                        .primary : .secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 70)
                
                // Trigger word section with consistent height
                ZStack(alignment: .center) {
                    if !triggerWords.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 7))
                                .foregroundColor(isSelected ? .accentColor.opacity(0.9) : .secondary.opacity(0.7))
                            
                            if triggerWords.count == 1 {
                                Text("\"\(triggerWords[0])...\"")
                                    .font(.system(size: 8, weight: .regular))
                                    .foregroundColor(isSelected ? .primary.opacity(0.8) : .secondary.opacity(0.7))
                                    .lineLimit(1)
                            } else {
                                Text("\"\(triggerWords[0])...\" +\(triggerWords.count - 1)")
                                    .font(.system(size: 8, weight: .regular))
                                    .foregroundColor(isSelected ? .primary.opacity(0.8) : .secondary.opacity(0.7))
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: 70)
                    }
                }
                .frame(height: 16)
            }
            
            shortcutLabel(for: shortcutIndex)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .onTapGesture(count: 2) {
            // Double tap to edit
            if let onEdit = onEdit {
                onEdit(self)
            }
        }
        .onTapGesture(count: 1) {
            // Single tap to select
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
                        onDelete(self)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func shortcutLabel(for index: Int?) -> some View {
        let labelHeight: CGFloat = 16
        if let index = index, index < 10 {
            let numberToShow = (index + 1) % 10
            HStack(spacing: 2) {
                Image(systemName: "option")
                    .font(.system(size: 9, weight: .medium))
                Text("\(numberToShow)")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.secondary)
            .frame(height: labelHeight)
            .transition(.opacity)
        } else {
            Spacer().frame(height: labelHeight)
        }
    }
    
    // Static method to create an "Add New" button with the same styling as the prompt icons
    static func addNewButton(action: @escaping () -> Void) -> some View {
        VStack(spacing: 4) {
            ZStack {
                // Dynamic background with blur effect - same styling as promptIcon
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(NSColor.controlBackgroundColor).opacity(0.95),
                                Color(NSColor.controlBackgroundColor).opacity(0.85)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.white.opacity(0.15),
                                        Color.white.opacity(0.05)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(
                        color: Color.black.opacity(0.1),
                        radius: 6,
                        x: 0,
                        y: 3
                    )
                
                // Decorative background elements (same as in promptIcon)
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.08),
                                Color.clear
                            ]),
                            center: .center,
                            startRadius: 1,
                            endRadius: 25
                        )
                    )
                    .frame(width: 50, height: 50)
                    .offset(x: -15, y: -15)
                    .blur(radius: 2)
                
                // Plus icon with same styling as the normal icons
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.9), Color.accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .frame(width: 48, height: 48)
            
            // Text label with matching styling
            VStack(spacing: 2) {
                Text("Add New")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 70)
                
                // Empty space matching the trigger word area height
                Spacer()
                    .frame(height: 16)
            }
            
            // Spacer to match shortcut label height
            Spacer().frame(height: 16)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}
