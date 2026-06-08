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

enum OnboardingShortcutSource {
    case primaryRecording
    case starterMode

    func action(modeTemplate: StarterModeTemplate) -> ShortcutAction {
        switch self {
        case .primaryRecording:
            return .primaryRecording
        case .starterMode:
            return .mode(modeTemplate.id)
        }
    }

    var usesPrimaryRecording: Bool {
        switch self {
        case .primaryRecording:
            return true
        case .starterMode:
            return false
        }
    }
}

struct OnboardingShortcutBehavior {
    let source: OnboardingShortcutSource
    let skipsIntroWhenConfigured: Bool
    let clearsOnIntro: Bool

    static func primaryRecording(
        skipsIntroWhenConfigured: Bool,
        clearsOnIntro: Bool
    ) -> OnboardingShortcutBehavior {
        OnboardingShortcutBehavior(
            source: .primaryRecording,
            skipsIntroWhenConfigured: skipsIntroWhenConfigured,
            clearsOnIntro: clearsOnIntro
        )
    }

    static func starterMode(clearsOnIntro: Bool) -> OnboardingShortcutBehavior {
        OnboardingShortcutBehavior(
            source: .starterMode,
            skipsIntroWhenConfigured: false,
            clearsOnIntro: clearsOnIntro
        )
    }
}

enum OnboardingExperienceLayout: Equatable {
    case transform
    case respond
}

struct OnboardingExperienceStep: Identifiable {
    let kind: OnboardingExperienceKind
    let starterModeKind: StarterModeKind
    let defaultModeKind: StarterModeKind
    let shortcutBehavior: OnboardingShortcutBehavior
    let layout: OnboardingExperienceLayout
    let requiresTextChangeForCompletion: Bool
    let requiresVerifiedAPIProvider: Bool
    let showsContextAwarenessAfterCompletion: Bool
    let systemImage: String
    let title: String
    let subtitle: String
    let sampleLabel: String
    let sampleText: String
    let fieldPlaceholder: String
    let initialFieldText: String
    let shortcutIntroTitle: String?
    let showsShortcutControl: Bool
    let configuredInstructionPrefix: String
    let configuredHorizontalInstructionSuffix: String
    let configuredWrappedInstructionSuffix: String

    var id: OnboardingExperienceKind { kind }

    var usesPrimaryRecordingShortcut: Bool {
        shortcutBehavior.source.usesPrimaryRecording
    }

    var shouldClearShortcutOnIntro: Bool {
        shortcutBehavior.clearsOnIntro
    }

    init(
        kind: OnboardingExperienceKind,
        starterModeKind: StarterModeKind,
        defaultModeKind: StarterModeKind,
        shortcutBehavior: OnboardingShortcutBehavior,
        layout: OnboardingExperienceLayout = .transform,
        requiresTextChangeForCompletion: Bool = true,
        requiresVerifiedAPIProvider: Bool = true,
        showsContextAwarenessAfterCompletion: Bool = false,
        systemImage: String,
        title: String,
        subtitle: String,
        sampleLabel: String = "Read this",
        sampleText: String,
        fieldPlaceholder: String,
        initialFieldText: String = "",
        shortcutIntroTitle: String? = nil,
        showsShortcutControl: Bool = true,
        configuredInstructionPrefix: String = "Press",
        configuredHorizontalInstructionSuffix: String = " and read the sample text, then press it again.",
        configuredWrappedInstructionSuffix: String = "Read the sample text, then press it again."
    ) {
        self.kind = kind
        self.starterModeKind = starterModeKind
        self.defaultModeKind = defaultModeKind
        self.shortcutBehavior = shortcutBehavior
        self.layout = layout
        self.requiresTextChangeForCompletion = requiresTextChangeForCompletion
        self.requiresVerifiedAPIProvider = requiresVerifiedAPIProvider
        self.showsContextAwarenessAfterCompletion = showsContextAwarenessAfterCompletion
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.sampleLabel = sampleLabel
        self.sampleText = sampleText
        self.fieldPlaceholder = fieldPlaceholder
        self.initialFieldText = initialFieldText
        self.shortcutIntroTitle = shortcutIntroTitle
        self.showsShortcutControl = showsShortcutControl
        self.configuredInstructionPrefix = configuredInstructionPrefix
        self.configuredHorizontalInstructionSuffix = configuredHorizontalInstructionSuffix
        self.configuredWrappedInstructionSuffix = configuredWrappedInstructionSuffix
    }

    func shortcutAction(modeTemplate: StarterModeTemplate) -> ShortcutAction {
        shortcutBehavior.source.action(modeTemplate: modeTemplate)
    }

    func shouldSkipShortcutIntro(hasConfiguredShortcut: Bool) -> Bool {
        shortcutBehavior.skipsIntroWhenConfigured && hasConfiguredShortcut
    }
}

enum OnboardingExperienceCatalog {
    static let steps: [OnboardingExperienceStep] = [
        OnboardingExperienceStep(
            kind: .dictation,
            starterModeKind: .clean,
            defaultModeKind: .clean,
            shortcutBehavior: .primaryRecording(
                skipsIntroWhenConfigured: false,
                clearsOnIntro: true
            ),
            requiresVerifiedAPIProvider: false,
            systemImage: "text.cursor",
            title: "Try a Simple Dictation",
            subtitle: "Uses a local transcription model for ultra-fast dictation.",
            sampleLabel: "Sample text",
            sampleText: "Please send the calendar invite before lunch.",
            fieldPlaceholder: "Your dictated text will appear here."
        ),
        OnboardingExperienceStep(
            kind: .enhance,
            starterModeKind: .enhance,
            defaultModeKind: .enhance,
            shortcutBehavior: .primaryRecording(
                skipsIntroWhenConfigured: true,
                clearsOnIntro: false
            ),
            systemImage: "sparkles",
            title: "Try Enhancement",
            subtitle: "Combines local transcription with an LLM to create a polished version.",
            sampleLabel: "Sample text",
            sampleText: "Um, tell the team we will meet on Thursday. Actually, no, Friday morning works better.",
            fieldPlaceholder: "Your enhanced message will appear here."
        ),
        OnboardingExperienceStep(
            kind: .email,
            starterModeKind: .email,
            defaultModeKind: .email,
            shortcutBehavior: .primaryRecording(
                skipsIntroWhenConfigured: true,
                clearsOnIntro: false
            ),
            showsContextAwarenessAfterCompletion: true,
            systemImage: "envelope.fill",
            title: "Write an Email",
            subtitle: "Turn your spoken note into a clean email draft with VoiceInk.",
            sampleLabel: "Sample text",
            sampleText: "Hi Morgan, um, I wanted to follow up on the proposal we discussed yesterday. I talked to Julie about it, and, like, like, she said you can call her at 555-0194 if you need the latest numbers. Thanks, Alex.",
            fieldPlaceholder: "Your formatted email will appear here."
        ),
        OnboardingExperienceStep(
            kind: .rewrite,
            starterModeKind: .rewrite,
            defaultModeKind: .clean,
            shortcutBehavior: .starterMode(clearsOnIntro: true),
            systemImage: "quote.bubble.fill",
            title: "Try Rewrite",
            subtitle: "Select the text on the screen, tell VoiceInk the changes you want, and VoiceInk will rewrite the text for you.",
            sampleLabel: "Sample text",
            sampleText: "Make it a checklist and add appropriate emoji for each item at the end.",
            fieldPlaceholder: "Text to rewrite will appear here.",
            initialFieldText: "For tomorrow's client update, I need to review the proposal, confirm the budget numbers, email the latest draft to the client, book the meeting room, prepare a short agenda, and share final notes with the team before the afternoon check-in.",
            configuredInstructionPrefix: "Select all text, press",
            configuredHorizontalInstructionSuffix: ", read the sample text aloud, then press it again.",
            configuredWrappedInstructionSuffix: "Read the sample text aloud, then press it again."
        ),
        OnboardingExperienceStep(
            kind: .rewriteFormat,
            starterModeKind: .rewrite,
            defaultModeKind: .clean,
            shortcutBehavior: .starterMode(clearsOnIntro: false),
            systemImage: "quote.bubble.fill",
            title: "Try Rewrite",
            subtitle: "Select the text on the screen, tell VoiceInk the changes you want, and VoiceInk will rewrite the text for you.",
            sampleLabel: "Sample text",
            sampleText: "Translate this into English.",
            fieldPlaceholder: "Text to rewrite will appear here.",
            initialFieldText: "म अहिले नेपालीमा बोलिरहेको छु, र म यो उपकरणलाई यसलाई अंग्रेजीमा अनुवाद गर्न भन्नेछु।",
            shortcutIntroTitle: "Let's try it once again.",
            showsShortcutControl: false,
            configuredInstructionPrefix: "Select all text, press",
            configuredHorizontalInstructionSuffix: ", read the sample text aloud, then press it again.",
            configuredWrappedInstructionSuffix: "Read the sample text aloud, then press it again."
        ),
        OnboardingExperienceStep(
            kind: .respond,
            starterModeKind: .assistant,
            defaultModeKind: .clean,
            shortcutBehavior: .starterMode(clearsOnIntro: true),
            layout: .respond,
            requiresTextChangeForCompletion: false,
            systemImage: "text.bubble.fill",
            title: "Ask a Quick Question",
            subtitle: "Ask quick questions and VoiceInk will serve you the answers.",
            sampleLabel: "Sample question",
            sampleText: "What is the capital city of the USA?",
            fieldPlaceholder: "",
            configuredHorizontalInstructionSuffix: ", ask the question, then press it again.",
            configuredWrappedInstructionSuffix: "Ask the question, then press it again."
        )
    ]
}
