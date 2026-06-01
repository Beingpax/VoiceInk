import Foundation

enum OnboardingExperienceKind: String, Identifiable, Hashable {
    case dictation
    case enhance
    case enhanceAgain
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
            sampleText: "It's raining today. We'll meet tomorrow.",
            fieldPlaceholder: "Your dictated text will appear here."
        ),
        OnboardingExperienceStep(
            kind: .enhance,
            starterModeKind: .enhance,
            title: "Try Enhancement",
            subtitle: "Combines local transcription with your AI provider to clean up rough speech.",
            sampleText: "Umm, we will meet tomorrow at 3 pm. Uhh, wait, not actually 3 pm but 7 p.m.",
            fieldPlaceholder: "Your enhanced message will appear here."
        ),
        OnboardingExperienceStep(
            kind: .enhanceAgain,
            starterModeKind: .enhance,
            title: "Try Enhancement",
            subtitle: "Combines local transcription with your AI provider to clean up rough speech.",
            sampleText: "Umm, I think we should, like, send the report today, today if possible.",
            fieldPlaceholder: "Your enhanced message will appear here."
        ),
        OnboardingExperienceStep(
            kind: .rewrite,
            starterModeKind: .rewrite,
            title: "Try Rewrite",
            subtitle: "Select text, say how to rewrite it, and let VoiceInk replace it.",
            sampleLabel: "Say this",
            sampleText: "Rewrite this to be clearer and more confident.",
            fieldPlaceholder: "Select this text, then use the shortcut.",
            initialFieldText: "I think the plan is kind of okay, but maybe we should make the next steps more clear before sharing it."
        ),
        OnboardingExperienceStep(
            kind: .rewriteFormat,
            starterModeKind: .rewrite,
            title: "Try Rewrite",
            subtitle: "Select text, say how to rewrite it, and let VoiceInk replace it.",
            sampleLabel: "Say this",
            sampleText: "Rewrite this with better structure and formatting.",
            fieldPlaceholder: "Select this text, then use the shortcut.",
            initialFieldText: "My wife called and asked me to bring five things from the grocery store: milk, bread, eggs, tomatoes, and coffee."
        ),
        OnboardingExperienceStep(
            kind: .respond,
            starterModeKind: .assistant,
            title: "Try Respond",
            subtitle: "Ask a question and keep the answer inside the recorder.",
            sampleLabel: "Ask this",
            sampleText: "What do you think about the future of AI in the next 10 years? Write it under 200 words.",
            fieldPlaceholder: ""
        )
    ]
}
