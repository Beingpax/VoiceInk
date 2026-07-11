import SwiftUI

@MainActor
final class OnboardingFlowController {
    private unowned let coordinator: OnboardingCoordinator

    init(coordinator: OnboardingCoordinator) {
        self.coordinator = coordinator
    }

    func goToPermissionsStep() {
        coordinator.storedStage = OnboardingStage.permissions.rawValue
    }

    func goToMicrophoneStep() {
        guard coordinator.requiredPermissionsGranted else { return }
        coordinator.storedStage = OnboardingStage.microphone.rawValue
    }

    func goToModelStep() {
        guard coordinator.requiredPermissionsGranted,
            coordinator.hasSelectedOnboardingMicrophone
        else { return }
        coordinator.storedStage = OnboardingStage.model.rawValue
    }

    func goToAPIStep(
        isTranscriptionSetupReady: Bool,
        aiService: AIService
    ) {
        guard coordinator.requiredPermissionsGranted,
            coordinator.hasSelectedOnboardingMicrophone,
            isTranscriptionSetupReady
        else { return }
        ensureDefaultOnboardingProvider()
        selectOnboardingProvider(coordinator.selectedOnboardingProvider, aiService: aiService)
        coordinator.storedStage = OnboardingStage.api.rawValue
    }

    func goBackToModelStep() {
        guard coordinator.requiredPermissionsGranted else {
            goToPermissionsStep()
            return
        }

        coordinator.storedStage = OnboardingStage.model.rawValue
    }

    func goToExperienceStep(
        isTranscriptionSetupReady: Bool,
        enhancementService: AIEnhancementService
    ) {
        guard coordinator.isReadyForExperience(isTranscriptionSetupReady: isTranscriptionSetupReady) else { return }
        coordinator.storedStage = OnboardingStage.experience.rawValue
        moveToExperienceStep(0, enhancementService: enhancementService)
    }

    func goToLicenseStep(isTranscriptionSetupReady: Bool) {
        guard coordinator.isReadyForExperience(isTranscriptionSetupReady: isTranscriptionSetupReady) else { return }
        coordinator.storedStage = OnboardingStage.license.rawValue
    }

    func goToContextAwarenessStep(isTranscriptionSetupReady: Bool) {
        guard coordinator.isReadyForExperience(isTranscriptionSetupReady: isTranscriptionSetupReady),
            coordinator.shouldShowContextAwarenessAfterCurrentExperience
        else {
            return
        }

        activateCleanTranscriptionMode()
        coordinator.storedStage = OnboardingStage.contextAwareness.rawValue
    }

    func goToTrustStep(isTranscriptionSetupReady: Bool) {
        guard coordinator.isReadyForExperience(isTranscriptionSetupReady: isTranscriptionSetupReady) else { return }
        coordinator.storedStage = OnboardingStage.trust.rawValue
    }

    func requestSkipAPISetup() {
        coordinator.isShowingSkipAPISetupWarning = true
    }

    func skipAPISetupAndContinue(
        isTranscriptionSetupReady: Bool,
        enhancementService: AIEnhancementService
    ) {
        coordinator.hasSkippedAPISetup = true
        coordinator.isSelectedAPIProviderVerified = false
        goToExperienceStep(
            isTranscriptionSetupReady: isTranscriptionSetupReady,
            enhancementService: enhancementService
        )
    }

    func goToExperiencePracticePhase() {
        withAnimation(.easeInOut(duration: 0.28)) {
            coordinator.isExperienceInIntroPhase = false
        }
    }

    func goToExperienceIntroPhase() {
        guard !coordinator.shouldSkipCurrentExperienceIntro else { return }

        withAnimation(.easeInOut(duration: 0.28)) {
            coordinator.isExperienceInIntroPhase = true
        }
    }

    func goBackFromExperiencePractice(enhancementService: AIEnhancementService) {
        if coordinator.shouldSkipCurrentExperienceIntro {
            goToPreviousExperienceStep(enhancementService: enhancementService)
        } else {
            goToExperienceIntroPhase()
        }
    }

    func goToPreviousExperienceStep(enhancementService: AIEnhancementService) {
        if coordinator.shouldShowContextAwarenessBeforeCurrentExperience {
            coordinator.experienceStepIndex = coordinator.normalizedExperienceStepIndex - 1
            activateCleanTranscriptionMode()
            coordinator.storedStage = OnboardingStage.contextAwareness.rawValue
            return
        }

        if coordinator.normalizedExperienceStepIndex > 0 {
            moveToExperienceStep(
                coordinator.normalizedExperienceStepIndex - 1,
                enhancementService: enhancementService
            )
        } else {
            coordinator.storedStage = OnboardingStage.api.rawValue
        }
    }

    func goToPreviousContextAwarenessStep(enhancementService: AIEnhancementService) {
        coordinator.storedStage = OnboardingStage.experience.rawValue
        coordinator.isExperienceInIntroPhase = false
        installCurrentExperienceMode(enhancementService: enhancementService)
        activateExperienceModeForDemo()
        refreshExperienceModeState(enhancementService: enhancementService)
    }

    func continueFromContextAwarenessStep(enhancementService: AIEnhancementService) {
        let nextIndex = coordinator.normalizedExperienceStepIndex + 1
        guard coordinator.activeExperienceSteps.indices.contains(nextIndex) else {
            return
        }

        coordinator.storedStage = OnboardingStage.experience.rawValue
        moveToExperienceStep(nextIndex, enhancementService: enhancementService)
    }

    func goToPreviousTrustStep(
        isTranscriptionSetupReady: Bool,
        enhancementService: AIEnhancementService
    ) {
        guard coordinator.isReadyForExperience(isTranscriptionSetupReady: isTranscriptionSetupReady) else {
            coordinator.storedStage = OnboardingStage.api.rawValue
            return
        }

        let previousIndex = max(coordinator.activeExperienceSteps.count - 1, 0)
        coordinator.storedStage = OnboardingStage.experience.rawValue
        coordinator.experienceStepIndex = previousIndex
        coordinator.isExperienceInIntroPhase = false
        installExperienceMode(at: previousIndex, enhancementService: enhancementService)
        activateExperienceModeForDemo()
        refreshExperienceModeState(enhancementService: enhancementService)
    }

    func goToPreviousLicenseStep(isTranscriptionSetupReady: Bool) {
        guard coordinator.isReadyForExperience(isTranscriptionSetupReady: isTranscriptionSetupReady) else {
            coordinator.storedStage = OnboardingStage.api.rawValue
            return
        }

        coordinator.storedStage = OnboardingStage.trust.rawValue
    }

    func advanceExperienceStep(
        isTranscriptionSetupReady: Bool,
        enhancementService: AIEnhancementService
    ) {
        guard coordinator.isCurrentExperienceReady(isTranscriptionSetupReady: isTranscriptionSetupReady) else {
            return
        }

        if coordinator.shouldShowContextAwarenessAfterCurrentExperience {
            goToContextAwarenessStep(isTranscriptionSetupReady: isTranscriptionSetupReady)
        } else if coordinator.isLastExperienceStep {
            goToTrustStep(isTranscriptionSetupReady: isTranscriptionSetupReady)
        } else {
            moveToExperienceStep(
                coordinator.normalizedExperienceStepIndex + 1,
                enhancementService: enhancementService
            )
        }
    }

    func startLicenseTrial(
        isTranscriptionSetupReady: Bool,
        onComplete: () -> Void
    ) {
        coordinator.licenseViewModel.startTrial()
        completeOnboarding(
            isTranscriptionSetupReady: isTranscriptionSetupReady,
            onComplete: onComplete
        )
    }

    func activateLicense() {
        Task { @MainActor in
            await coordinator.licenseViewModel.validateLicense()
        }
    }

    func reconcileStage(
        isTranscriptionSetupReady: Bool,
        enhancementService: AIEnhancementService
    ) {
        if coordinator.stage == .microphone && !coordinator.requiredPermissionsGranted {
            goToPermissionsStep()
        }

        if coordinator.stage == .model
            && (!coordinator.requiredPermissionsGranted || !coordinator.hasSelectedOnboardingMicrophone)
        {
            goToFirstIncompleteSetupStep(isTranscriptionSetupReady: isTranscriptionSetupReady)
        }

        if coordinator.stage == .api
            && (!coordinator.requiredPermissionsGranted || !coordinator.hasSelectedOnboardingMicrophone
                || !isTranscriptionSetupReady)
        {
            goToFirstIncompleteSetupStep(isTranscriptionSetupReady: isTranscriptionSetupReady)
        }

        if (coordinator.stage == .experience || coordinator.stage == .contextAwareness || coordinator.stage == .trust
            || coordinator.stage == .license)
            && !coordinator.isReadyForExperience(isTranscriptionSetupReady: isTranscriptionSetupReady)
        {
            goToFirstIncompleteSetupStep(isTranscriptionSetupReady: isTranscriptionSetupReady)
        }

        if coordinator.stage == .experience
            && coordinator.isReadyForExperience(isTranscriptionSetupReady: isTranscriptionSetupReady)
            && !coordinator.isExperienceModeInstalled
        {
            installCurrentExperienceMode(enhancementService: enhancementService)
        }

        if coordinator.stage == .contextAwareness
            && coordinator.isReadyForExperience(isTranscriptionSetupReady: isTranscriptionSetupReady)
        {
            activateCleanTranscriptionMode()
        }
    }

    func goToFirstIncompleteSetupStep(isTranscriptionSetupReady: Bool) {
        if !coordinator.requiredPermissionsGranted {
            coordinator.storedStage = OnboardingStage.permissions.rawValue
        } else if !coordinator.hasSelectedOnboardingMicrophone {
            coordinator.storedStage = OnboardingStage.microphone.rawValue
        } else if !isTranscriptionSetupReady {
            coordinator.storedStage = OnboardingStage.model.rawValue
        } else {
            coordinator.storedStage = OnboardingStage.api.rawValue
        }
    }

    func downloadTranscriptionModel(
        _ model: FluidAudioModel,
        modelManager: FluidAudioModelManager
    ) {
        guard coordinator.requiredPermissionsGranted,
            coordinator.hasSelectedOnboardingMicrophone,
            !modelManager.isFluidAudioModelDownloaded(model),
            !modelManager.isFluidAudioModelDownloading(model)
        else {
            return
        }

        Task {
            await modelManager.downloadFluidAudioModel(model)
        }
    }

    func moveToExperienceStep(
        _ index: Int,
        enhancementService: AIEnhancementService
    ) {
        guard coordinator.activeExperienceSteps.indices.contains(index) else {
            return
        }

        coordinator.experienceStepIndex = index
        coordinator.isExperienceInIntroPhase = shouldStartExperienceInIntroPhase(
            for: coordinator.activeExperienceSteps[index]
        )
        resetExperienceText(at: index)
        installExperienceMode(at: index, enhancementService: enhancementService)
        activateExperienceModeForDemo()
        clearExperienceShortcutForIntroIfNeeded()
        refreshExperienceModeState(enhancementService: enhancementService)
    }

    func completeOnboarding(
        isTranscriptionSetupReady: Bool,
        onComplete: () -> Void
    ) {
        guard
            coordinator.stage == .license
                || coordinator.isCurrentExperienceReady(isTranscriptionSetupReady: isTranscriptionSetupReady)
        else {
            return
        }

        OnboardingStorageKeys.onboardingKeys.forEach {
            coordinator.defaults.removeObject(forKey: $0)
        }
        activateCleanTranscriptionMode()
        onComplete()
    }

    func skipOnboarding(onComplete: () -> Void) {
        OnboardingStorageKeys.onboardingKeys.forEach {
            coordinator.defaults.removeObject(forKey: $0)
        }
        onComplete()
    }

    func refreshAPIVerification() {
        coordinator.isSelectedAPIProviderVerified = APIKeyManager.shared.hasAPIKey(
            forProvider: coordinator.selectedOnboardingProvider.rawValue
        )

        if coordinator.isSelectedAPIProviderVerified {
            coordinator.hasSkippedAPISetup = false
        }
    }

    func refreshTranscriptionSetupVerification() {
        ensureDefaultOnboardingTranscriptionProvider()

        guard let provider = coordinator.selectedOnboardingTranscriptionProvider else {
            coordinator.isSelectedTranscriptionProviderVerified = false
            return
        }

        coordinator.isSelectedTranscriptionProviderVerified = APIKeyManager.shared.hasAPIKey(
            forProvider: provider.providerKey
        )
    }

    func selectOnboardingTranscriptionSetup(_ kind: OnboardingTranscriptionSetupKind) {
        coordinator.storedTranscriptionSetupKind = kind.rawValue
        ensureDefaultOnboardingTranscriptionProvider()
        refreshTranscriptionSetupVerification()
    }

    func ensureDefaultOnboardingTranscriptionProvider() {
        let options = coordinator.onboardingTranscriptionProviderOptions
        if options.contains(where: {
            $0.providerKey.caseInsensitiveCompare(coordinator.storedOnboardingTranscriptionProvider) == .orderedSame
        }) {
            return
        }

        let defaultProvider = coordinator.recommendedOnboardingTranscriptionProvider ?? options.first
        coordinator.storedOnboardingTranscriptionProvider = defaultProvider?.providerKey ?? ""
    }

    func selectOnboardingTranscriptionProvider(_ providerKey: String) {
        guard
            coordinator.onboardingTranscriptionProviderOptions.contains(where: {
                $0.providerKey.caseInsensitiveCompare(providerKey) == .orderedSame
            })
        else { return }

        coordinator.storedOnboardingTranscriptionProvider = providerKey
        refreshTranscriptionSetupVerification()
    }

    func ensureDefaultOnboardingProvider() {
        if let storedProvider = AIProvider(rawValue: coordinator.storedOnboardingAIProvider),
            coordinator.onboardingProviderOptions.contains(storedProvider)
        {
            return
        }

        let defaultProvider: AIProvider =
            coordinator.onboardingProviderOptions.contains(.groq)
            ? .groq
            : coordinator.onboardingProviderOptions.first ?? .groq
        coordinator.storedOnboardingAIProvider = defaultProvider.rawValue
    }

    func selectOnboardingProvider(_ provider: AIProvider, aiService: AIService) {
        guard coordinator.onboardingProviderOptions.contains(provider) else { return }

        coordinator.storedOnboardingAIProvider = provider.rawValue

        if APIKeyManager.shared.hasAPIKey(forProvider: provider.rawValue) {
            aiService.selectedProvider = provider
            aiService.selectModel(provider.defaultModel, for: provider)
        }

        refreshAPIVerification()
    }

    func installExperienceMode(
        at index: Int,
        enhancementService: AIEnhancementService
    ) {
        guard coordinator.activeExperienceSteps.indices.contains(index) else {
            return
        }

        var seenKinds = Set<StarterModeKind>()
        let installedKinds = coordinator.activeExperienceSteps
            .prefix(index + 1)
            .map(\.starterModeKind)
            .filter { seenKinds.insert($0).inserted }

        let installedSteps = Array(coordinator.activeExperienceSteps.prefix(index + 1))

        let seedResult = StarterModePromptSeeder.ensurePrompts(
            for: installedKinds,
            in: enhancementService.customPrompts
        )
        if seedResult.didChange {
            enhancementService.customPrompts = seedResult.prompts
        }

        StarterModeFactory.install(
            kinds: installedKinds,
            provider: coordinator.selectedOnboardingProvider,
            modelName: coordinator.selectedOnboardingProvider.defaultModel,
            transcriptionModelName: coordinator.selectedOnboardingTranscriptionModelName
                ?? StarterModeFactory.defaultTranscriptionModelName,
            isRealtimeTranscriptionEnabled: coordinator.selectedOnboardingTranscriptionUsesRealtime,
            selectedLanguage: coordinator.selectedOnboardingTranscriptionLanguage
        )

        removeModeShortcutStorageForPrimaryRecordingSteps(installedSteps)
        applyDefaultMode(for: coordinator.activeExperienceSteps[index])
    }

    func installCurrentExperienceMode(enhancementService: AIEnhancementService) {
        guard coordinator.stage == .experience else { return }
        installExperienceMode(
            at: coordinator.normalizedExperienceStepIndex,
            enhancementService: enhancementService
        )
        refreshExperienceModeState(enhancementService: enhancementService)
    }

    func refreshExperienceModeState(enhancementService: AIEnhancementService) {
        let hasRequiredPrompts = StarterModePromptSeeder.hasPrompts(
            for: [coordinator.experienceModeTemplate.kind],
            in: enhancementService.customPrompts
        )

        coordinator.isExperienceModeInstalled =
            StarterModeFactory.isInstalled(kind: coordinator.experienceModeTemplate.kind) && hasRequiredPrompts
        coordinator.hasExperienceModeShortcut = ShortcutStore.shortcut(for: coordinator.experienceShortcutAction) != nil
    }

    func clearExperienceShortcutForIntroIfNeeded() {
        guard coordinator.stage == .experience,
            coordinator.isExperienceInIntroPhase,
            coordinator.experienceStep.shouldClearShortcutOnIntro,
            !coordinator.clearedExperienceShortcutActions.contains(coordinator.experienceShortcutAction)
        else {
            return
        }

        var clearedActions = coordinator.clearedExperienceShortcutActions
        clearedActions.insert(coordinator.experienceShortcutAction)
        coordinator.clearedExperienceShortcutActions = clearedActions
        ShortcutStore.setShortcut(nil, for: coordinator.experienceShortcutAction)
    }

    func activateExperienceModeForDemo() {
        guard coordinator.stage == .experience,
            let config = ModeManager.shared.getConfiguration(with: coordinator.experienceModeTemplate.id)
        else {
            return
        }

        applyDefaultMode(for: coordinator.experienceStep)
        ModeManager.shared.setActiveConfiguration(config)
    }

    func activateCleanTranscriptionMode() {
        guard let cleanTemplate = StarterModeCatalog.templates.first(where: { $0.kind == .clean }),
            let cleanConfig = ModeManager.shared.getConfiguration(with: cleanTemplate.id)
        else {
            return
        }

        ModeManager.shared.setAsDefault(configId: cleanConfig.id)
        ModeManager.shared.setActiveConfiguration(cleanConfig)
    }

    private func applyDefaultMode(for step: OnboardingExperienceStep) {
        setDefaultStarterMode(step.defaultModeKind)
    }

    private func setDefaultStarterMode(_ kind: StarterModeKind) {
        guard let template = StarterModeCatalog.templates.first(where: { $0.kind == kind }),
            ModeManager.shared.getConfiguration(with: template.id) != nil,
            ModeManager.shared.getDefaultConfiguration()?.id != template.id
        else {
            return
        }

        ModeManager.shared.setAsDefault(configId: template.id)
    }

    private func shouldStartExperienceInIntroPhase(for step: OnboardingExperienceStep) -> Bool {
        !step.shouldSkipShortcutIntro(
            hasConfiguredShortcut: ShortcutStore.shortcut(for: shortcutAction(for: step)) != nil
        )
    }

    private func removeModeShortcutStorageForPrimaryRecordingSteps(_ steps: [OnboardingExperienceStep]) {
        var removedTemplateIds = Set<UUID>()

        for step in steps where step.usesPrimaryRecordingShortcut {
            let template = modeTemplate(for: step)
            guard removedTemplateIds.insert(template.id).inserted else {
                continue
            }

            let action = ShortcutAction.mode(template.id)
            if ShortcutStore.rawShortcut(for: action) != nil || ShortcutStore.isShortcutCleared(for: action) {
                ShortcutStore.removeShortcutStorage(for: action)
            }
        }
    }

    private func shortcutAction(for step: OnboardingExperienceStep) -> ShortcutAction {
        step.shortcutAction(modeTemplate: modeTemplate(for: step))
    }

    private func modeTemplate(for step: OnboardingExperienceStep) -> StarterModeTemplate {
        StarterModeCatalog.templates.first { $0.kind == step.starterModeKind } ?? StarterModeCatalog.templates[0]
    }

    func resetExperienceText(at index: Int) {
        guard coordinator.activeExperienceSteps.indices.contains(index) else {
            return
        }

        let step = coordinator.activeExperienceSteps[index]
        var updatedText = coordinator.experienceTextByKind
        updatedText[step.kind] = step.initialFieldText
        coordinator.experienceTextByKind = updatedText
    }
}
