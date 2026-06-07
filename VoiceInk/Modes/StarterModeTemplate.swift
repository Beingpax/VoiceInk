import Foundation

enum StarterModeKind: String, CaseIterable, Identifiable {
    case clean
    case enhance
    case email
    case rewrite
    case assistant

    var id: String { rawValue }
}

struct StarterModeTemplate: Identifiable {
    let kind: StarterModeKind
    let id: UUID
    let name: String
    let icon: ModeIcon
    let description: String
    let guidance: String
    let promptId: UUID?
    let outputMode: ModeOutputMode
    let usesAIEnhancement: Bool
    let useSelectedTextContext: Bool
    let useScreenCapture: Bool
    let isDefault: Bool

    var featureLabels: [String] {
        var labels = ["Parakeet V3", "Realtime"]

        if usesAIEnhancement {
            labels.append("AI")
        } else {
            labels.append("No AI")
        }

        if outputMode == .respond {
            labels.append("Respond")
        } else {
            labels.append("Paste")
        }

        return labels
    }
}

enum StarterModeCatalog {
    static let templates: [StarterModeTemplate] = [
        StarterModeTemplate(
            kind: .clean,
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            name: "Dictation",
            icon: .symbol("mic.fill"),
            description: "Fast local transcription with no AI enhancement.",
            guidance: "Use this when you want the quickest possible voice-to-text result. It records with Parakeet V3 and pastes the transcript as-is.",
            promptId: nil,
            outputMode: .paste,
            usesAIEnhancement: false,
            useSelectedTextContext: false,
            useScreenCapture: false,
            isDefault: true
        ),
        StarterModeTemplate(
            kind: .enhance,
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
            name: "Enhancement",
            icon: .symbol("sparkles"),
            description: "Clean up dictated text while preserving your meaning.",
            guidance: "Use this for everyday writing when you want grammar, flow, and light formatting improved before the result is pasted.",
            promptId: PromptTemplates.defaultPromptId,
            outputMode: .paste,
            usesAIEnhancement: true,
            useSelectedTextContext: true,
            useScreenCapture: true,
            isDefault: false
        ),
        StarterModeTemplate(
            kind: .email,
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
            name: "Email",
            icon: .symbol("envelope.fill"),
            description: "Turn a rough thought into a clean email.",
            guidance: "Use this after selecting relevant text or opening the related window. VoiceInk uses that context to shape a clear email draft.",
            promptId: PromptTemplates.emailPromptId,
            outputMode: .paste,
            usesAIEnhancement: true,
            useSelectedTextContext: true,
            useScreenCapture: true,
            isDefault: false
        ),
        StarterModeTemplate(
            kind: .rewrite,
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!,
            name: "Rewrite",
            icon: .symbol("quote.bubble.fill"),
            description: "Rewrite selected or dictated text with better clarity.",
            guidance: "Use this when you have text selected and want a stronger version. The selected text is available as context for the rewrite.",
            promptId: PromptTemplates.rewritePromptId,
            outputMode: .paste,
            usesAIEnhancement: true,
            useSelectedTextContext: true,
            useScreenCapture: false,
            isDefault: false
        ),
        StarterModeTemplate(
            kind: .assistant,
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000005")!,
            name: "Assistant",
            icon: .symbol("bubble.left.and.bubble.right.fill"),
            description: "Ask a question and keep the answer in the recorder.",
            guidance: "Use this for answers, summaries, and follow-ups. Instead of pasting, VoiceInk keeps the conversation inside the recorder.",
            promptId: PromptTemplates.assistantPromptId,
            outputMode: .respond,
            usesAIEnhancement: true,
            useSelectedTextContext: false,
            useScreenCapture: false,
            isDefault: false
        )
    ]

    static var ids: Set<UUID> {
        Set(templates.map(\.id))
    }
}
