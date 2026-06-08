import SwiftUI

@MainActor
final class OnboardingCoordinator: ObservableObject {
    let licenseViewModel = LicenseViewModel()

    @Published var storedStage: String {
        didSet {
            defaults.set(storedStage, forKey: OnboardingStorageKeys.stage)
        }
    }

    @Published var storedActivePermission: String {
        didSet {
            defaults.set(storedActivePermission, forKey: OnboardingStorageKeys.activePermission)
        }
    }

    @Published var hasRequestedScreenRecording: Bool {
        didSet {
            defaults.set(hasRequestedScreenRecording, forKey: OnboardingStorageKeys.requestedScreenRecording)
        }
    }

    @Published var experienceStepIndex: Int {
        didSet {
            defaults.set(experienceStepIndex, forKey: OnboardingStorageKeys.experienceIndex)
        }
    }

    @Published var storedOnboardingAIProvider: String {
        didSet {
            defaults.set(storedOnboardingAIProvider, forKey: OnboardingStorageKeys.aiProvider)
        }
    }

    @Published var hasSkippedAPISetup: Bool {
        didSet {
            defaults.set(hasSkippedAPISetup, forKey: OnboardingStorageKeys.skippedAPISetup)
        }
    }

    @Published var permissionStatuses: [OnboardingPermissionKind: OnboardingPermissionStatus] = [:]
    @Published var isSelectedAPIProviderVerified = false
    @Published var isShowingSkipAPISetupWarning = false
    @Published var hasExperienceModeShortcut = false
    @Published var isExperienceModeInstalled = false
    @Published var experienceTextByKind: [OnboardingExperienceKind: String] = [:]
    @Published var isExperienceInIntroPhase = true
    @Published var clearedExperienceShortcutActions: Set<ShortcutAction> = []

    let defaults: UserDefaults
    var refreshTask: Task<Void, Never>?
    lazy var flow = OnboardingFlowController(coordinator: self)
    lazy var permissions = OnboardingPermissionController(coordinator: self)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.storedStage = defaults.string(forKey: OnboardingStorageKeys.stage) ?? OnboardingStage.permissions.rawValue
        self.storedActivePermission = defaults.string(forKey: OnboardingStorageKeys.activePermission) ?? OnboardingPermissionKind.microphone.rawValue
        self.hasRequestedScreenRecording = defaults.bool(forKey: OnboardingStorageKeys.requestedScreenRecording)
        self.experienceStepIndex = defaults.integer(forKey: OnboardingStorageKeys.experienceIndex)
        self.storedOnboardingAIProvider = defaults.string(forKey: OnboardingStorageKeys.aiProvider) ?? AIProvider.groq.rawValue
        self.hasSkippedAPISetup = defaults.bool(forKey: OnboardingStorageKeys.skippedAPISetup)
    }

    deinit {
        refreshTask?.cancel()
    }

    var stage: OnboardingStage {
        if let stage = OnboardingStage(rawValue: storedStage) {
            return stage
        }

        if storedStage == "starterMode" || storedStage == "shortcut" {
            return .experience
        }

        return storedStage == "parakeet" ? .model : .permissions
    }

    var activePermission: OnboardingPermissionKind {
        OnboardingPermissionKind(rawValue: storedActivePermission) ?? .microphone
    }

    var requiredPermissionsGranted: Bool {
        OnboardingPermissionKind.required.allSatisfy { permissions.status(for: $0).isGranted }
    }

    var hasSelectedOnboardingMicrophone: Bool {
        defaults.audioInputModeRawValue == AudioInputMode.custom.rawValue &&
            defaults.selectedAudioDeviceUID != nil
    }

    var currentStepNumber: Int {
        if stage == .experience {
            return experienceStepNumber(for: normalizedExperienceStepIndex)
        }

        if stage == .contextAwareness {
            return contextAwarenessStepNumber
        }

        if stage == .trust {
            return OnboardingStage.baseStepCount + activeExperienceSteps.count + contextAwarenessStepCount + 1
        }

        if stage == .license {
            return OnboardingStage.baseStepCount + activeExperienceSteps.count + contextAwarenessStepCount + 2
        }

        return stage.stepNumber
    }

    var totalStepCount: Int {
        OnboardingStage.baseStepCount + activeExperienceSteps.count + contextAwarenessStepCount + 2
    }

    var experienceStep: OnboardingExperienceStep {
        if activeExperienceSteps.indices.contains(normalizedExperienceStepIndex) {
            return activeExperienceSteps[normalizedExperienceStepIndex]
        }

        return OnboardingExperienceCatalog.steps[0]
    }

    var experienceModeTemplate: StarterModeTemplate {
        StarterModeCatalog.templates.first { $0.kind == experienceStep.starterModeKind } ?? StarterModeCatalog.templates[0]
    }

    var normalizedExperienceStepIndex: Int {
        min(max(experienceStepIndex, 0), max(activeExperienceSteps.count - 1, 0))
    }

    var isLastExperienceStep: Bool {
        normalizedExperienceStepIndex == activeExperienceSteps.count - 1
    }

    var experienceShortcutAction: ShortcutAction {
        experienceStep.shortcutAction(modeTemplate: experienceModeTemplate)
    }

    var shouldSkipCurrentExperienceIntro: Bool {
        experienceStep.shouldSkipShortcutIntro(
            hasConfiguredShortcut: ShortcutStore.shortcut(for: experienceShortcutAction) != nil
        )
    }

    var shouldShowContextAwarenessAfterCurrentExperience: Bool {
        let nextIndex = normalizedExperienceStepIndex + 1
        return experienceStep.showsContextAwarenessAfterCompletion &&
            activeExperienceSteps.indices.contains(nextIndex)
    }

    var shouldShowContextAwarenessBeforeCurrentExperience: Bool {
        let previousIndex = normalizedExperienceStepIndex - 1
        guard activeExperienceSteps.indices.contains(previousIndex) else {
            return false
        }

        return activeExperienceSteps[previousIndex].showsContextAwarenessAfterCompletion
    }

    var isShowingExperienceIntroPhase: Bool {
        isExperienceInIntroPhase && !shouldSkipCurrentExperienceIntro
    }

    var currentExperienceText: Binding<String> {
        Binding(
            get: { [weak self] in
                guard let self else { return "" }
                return experienceTextByKind[experienceStep.kind] ?? experienceStep.initialFieldText
            },
            set: { [weak self] newValue in
                guard let self else { return }
                var updatedText = experienceTextByKind
                updatedText[experienceStep.kind] = newValue
                experienceTextByKind = updatedText
            }
        )
    }

    var isCurrentExperienceComplete: Bool {
        if !experienceStep.requiresTextChangeForCompletion {
            return true
        }

        let text = experienceTextByKind[experienceStep.kind] ?? ""
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let initialText = experienceStep.initialFieldText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !initialText.isEmpty {
            return !trimmedText.isEmpty && trimmedText != initialText
        }

        return !trimmedText.isEmpty
    }

    var onboardingProviderOptions: [AIProvider] {
        let preferredOrder: [AIProvider] = [
            .groq,
            .cerebras,
            .gemini,
            .openAI,
            .openRouter,
            .anthropic,
            .mistral
        ]

        let supportedProviders = AIProvider.allCases.filter { provider in
            provider.supportsEnhancement &&
                provider.requiresAPIKey &&
                provider != .custom
        }

        return supportedProviders.sorted { first, second in
            let firstIndex = preferredOrder.firstIndex(of: first) ?? Int.max
            let secondIndex = preferredOrder.firstIndex(of: second) ?? Int.max

            if firstIndex != secondIndex {
                return firstIndex < secondIndex
            }

            return first.rawValue < second.rawValue
        }
    }

    var activeExperienceSteps: [OnboardingExperienceStep] {
        if hasSkippedAPISetup && !isSelectedAPIProviderVerified {
            return OnboardingExperienceCatalog.steps.filter { !$0.requiresVerifiedAPIProvider }
        }

        return OnboardingExperienceCatalog.steps
    }

    private var contextAwarenessInsertionIndices: [Int] {
        activeExperienceSteps.indices.compactMap { index in
            let nextIndex = index + 1
            guard activeExperienceSteps[index].showsContextAwarenessAfterCompletion,
                  activeExperienceSteps.indices.contains(nextIndex) else {
                return nil
            }

            return nextIndex
        }
    }

    private var contextAwarenessStepCount: Int {
        contextAwarenessInsertionIndices.count
    }

    private var contextAwarenessStepNumber: Int {
        guard let insertionIndex = contextAwarenessInsertionIndices.first else {
            return OnboardingStage.baseStepCount + activeExperienceSteps.count + 1
        }

        return OnboardingStage.baseStepCount + insertionIndex + 1
    }

    private func experienceStepNumber(for index: Int) -> Int {
        let priorContextScreens = contextAwarenessInsertionIndices.filter { $0 <= index }.count
        return OnboardingStage.baseStepCount + index + priorContextScreens + 1
    }

    var selectedOnboardingProvider: AIProvider {
        if let storedProvider = AIProvider(rawValue: storedOnboardingAIProvider),
           onboardingProviderOptions.contains(storedProvider) {
            return storedProvider
        }

        if onboardingProviderOptions.contains(.groq) {
            return .groq
        }

        return onboardingProviderOptions.first ?? .groq
    }

    var requiredTranscriptionModel: FluidAudioModel? {
        TranscriptionModelRegistry.models
            .compactMap { $0 as? FluidAudioModel }
            .first { $0.name == "parakeet-tdt-0.6b-v3" }
    }

    func selectedOnboardingProviderBinding(aiService: AIService) -> Binding<AIProvider> {
        Binding(
            get: { [weak self] in
                self?.selectedOnboardingProvider ?? .groq
            },
            set: { [weak self] provider in
                self?.flow.selectOnboardingProvider(provider, aiService: aiService)
            }
        )
    }

    func isTranscriptionModelDownloaded(using modelManager: FluidAudioModelManager) -> Bool {
        guard let requiredTranscriptionModel else { return false }
        return modelManager.isFluidAudioModelDownloaded(requiredTranscriptionModel)
    }

    func isReadyForExperience(isTranscriptionModelDownloaded: Bool) -> Bool {
        requiredPermissionsGranted &&
            hasSelectedOnboardingMicrophone &&
            isTranscriptionModelDownloaded &&
            (isSelectedAPIProviderVerified || hasSkippedAPISetup)
    }

    func isCurrentExperienceReady(isTranscriptionModelDownloaded: Bool) -> Bool {
        isReadyForExperience(isTranscriptionModelDownloaded: isTranscriptionModelDownloaded) &&
            isExperienceModeInstalled &&
            hasExperienceModeShortcut
    }

}

enum OnboardingStorageKeys {
    static let stage = "onboardingStage"
    static let activePermission = "onboardingActivePermission"
    static let requestedScreenRecording = "onboardingRequestedScreenRecording"
    static let experienceIndex = "onboardingExperienceIndex"
    static let aiProvider = "onboardingAIProvider"
    static let skippedAPISetup = "onboardingSkippedAPISetup"

    static let onboardingKeys = [
        stage,
        activePermission,
        requestedScreenRecording,
        aiProvider,
        skippedAPISetup,
        experienceIndex,
        "onboardingStarterModeIndex"
    ]
}
