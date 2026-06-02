import Foundation

enum OnboardingExperienceKind: String, Identifiable, Hashable {
    case dictation
    case enhance
    case email
    case rewrite
    case rewriteFormat
    case respond

    var id: String { rawValue }
}

struct OnboardingExperienceStep: Identifiable {
    let kind: OnboardingExperienceKind
    let starterModeKind: StarterModeKind
    let title: String
    let subtitle: String
    let sampleLabel: String
    let sampleText: String
    let fieldPlaceholder: String
    let initialFieldText: String

    var id: OnboardingExperienceKind { kind }

    init(
        kind: OnboardingExperienceKind,
        starterModeKind: StarterModeKind,
        title: String,
        subtitle: String,
        sampleLabel: String = "Read this",
        sampleText: String,
        fieldPlaceholder: String,
        initialFieldText: String = ""
    ) {
        self.kind = kind
        self.starterModeKind = starterModeKind
        self.title = title
        self.subtitle = subtitle
        self.sampleLabel = sampleLabel
        self.sampleText = sampleText
        self.fieldPlaceholder = fieldPlaceholder
        self.initialFieldText = initialFieldText
    }
}

enum OnboardingExperienceCatalog {
    static let steps: [OnboardingExperienceStep] = [
        OnboardingExperienceStep(
            kind: .dictation,
            starterModeKind: .clean,
            title: "Try a Simple Dictation",
            subtitle: "Uses a local transcription model for ultra-fast dictation.",
            sampleLabel: "Sample text",
            sampleText: "Please send the calendar invite before lunch.",
            fieldPlaceholder: "Your dictated text will appear here."
        ),
        OnboardingExperienceStep(
            kind: .enhance,
            starterModeKind: .enhance,
            title: "Try Enhancement",
            subtitle: "Combines local transcription with an LLM to create a polished version.",
            sampleLabel: "Sample text",
            sampleText: "Um, tell the team we will meet on Thursday. Actually, no, Friday morning works better.",
            fieldPlaceholder: "Your enhanced message will appear here."
        ),
        OnboardingExperienceStep(
            kind: .email,
            starterModeKind: .email,
            title: "Write an Email",
            subtitle: "Turn your spoken note into a clean email draft with VoiceInk.",
            sampleLabel: "Sample text",
            sampleText: "Hello Paul, um, we'll meet tomorrow at nine PM, right, for the business meeting we had last week. Thanks John.",
            fieldPlaceholder: "Your formatted email will appear here."
        ),
        OnboardingExperienceStep(
            kind: .rewrite,
            starterModeKind: .rewrite,
            title: "Try Rewrite",
            subtitle: "Start with selected text, tell VoiceInk what change you want, and it will replace the text for you.",
            sampleLabel: "Sample text",
            sampleText: "Make it a checklist and add appropriate emoji for each item at the end.",
            fieldPlaceholder: "Text to rewrite will appear here.",
            initialFieldText: "For tomorrow's client update, I need to review the proposal, confirm the budget numbers, email the latest draft to the client, book the meeting room, prepare a short agenda, and share final notes with the team before the afternoon check-in."
        ),
        OnboardingExperienceStep(
            kind: .rewriteFormat,
            starterModeKind: .rewrite,
            title: "Try Rewrite",
            subtitle: "Start with selected text, tell VoiceInk what change you want, and it will replace the text for you.",
            sampleLabel: "Sample text",
            sampleText: "Translate this into English.",
            fieldPlaceholder: "Text to rewrite will appear here.",
            initialFieldText: "म अहिले नेपालीमा बोलिरहेको छु, र म यो उपकरणलाई यसलाई अंग्रेजीमा अनुवाद गर्न भन्नेछु।"
        ),
        OnboardingExperienceStep(
            kind: .respond,
            starterModeKind: .assistant,
            title: "Ask a Quick Question",
            subtitle: "Ask quick questions and VoiceInk will serve you the answers.",
            sampleLabel: "Sample question",
            sampleText: "What is the capital city of the USA?",
            fieldPlaceholder: ""
        )
    ]
}
