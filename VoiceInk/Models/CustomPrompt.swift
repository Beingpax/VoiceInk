import Foundation

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
    case codeFill = "chevron.left.forwardslash.chevron.right.fill"
    case terminalFill = "terminal.fill"
    case gearFill = "gearshape.fill"
    
    // Content
    case blogFill = "doc.text.image.fill"
    case notesFill = "note.text"
    case bookFill = "book.fill"
    case bookmarkFill = "bookmark.fill"
    case pencilFill = "pencil.circle.fill"
    
    // Media & Creative
    case videoFill = "video.fill"
    case micFill = "mic.fill"
    case musicFill = "music.note.list"
    case photoFill = "photo.fill"
    case brushFill = "paintbrush.fill"
    
    // Workflow icons
    case workflowFill = "arrow.triangle.branch"
    case automationFill = "wand.and.stars"
    
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
            
        // Workflow icons
        case .workflowFill: return "Workflow"
        case .automationFill: return "Automation"
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
    
    init(
        id: UUID = UUID(),
        title: String,
        promptText: String,
        isActive: Bool = false,
        icon: PromptIcon = .documentFill,
        description: String? = nil,
        isPredefined: Bool = false
    ) {
        self.id = id
        self.title = title
        self.promptText = promptText
        self.isActive = isActive
        self.icon = icon
        self.description = description
        self.isPredefined = isPredefined
    }
}

struct Workflow: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var prompt: String
    var jsonOutput: String
    
    init(
        id: UUID = UUID(),
        name: String = "",
        prompt: String = "",
        jsonOutput: String = "{}"
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.jsonOutput = jsonOutput
    }
}