import Foundation

enum OnboardingExperienceKind: String, Identifiable, Hashable {
    case dictation
    case enhance
    case email

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
    let configuredInstruction: String

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
        configuredInstruction: String = "Press your shortcut, read the sample text, then press it again."
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
        self.configuredInstruction = configuredInstruction
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
            subtitle: String(localized: "Uses your configured transcription model for fast dictation."),
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
            subtitle: String(localized: "Combines transcription with an LLM to create a polished version."),
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
            sampleText:
                "Hi Morgan, um, I wanted to follow up on the proposal we discussed yesterday. I talked to Julie about it, and, like, like, she said you can call her at 555-0194 if you need the latest numbers. Thanks, Alex.",
            fieldPlaceholder: "Your formatted email will appear here."
        ),
    ]
}
