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
              coordinator.hasSelectedOnboardingMicrophone else { return }
        coordinator.storedStage = OnboardingStage.model.rawValue
    }

    func goToAPIStep(
        isTranscriptionModelDownloaded: Bool,
        aiService: AIService
    ) {
        guard coordinator.requiredPermissionsGranted,
              coordinator.hasSelectedOnboardingMicrophone,
              isTranscriptionModelDownloaded else { return }
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
        isTranscriptionModelDownloaded: Bool,
        enhancementService: AIEnhancementService
    ) {
        guard coordinator.isReadyForExperience(isTranscriptionModelDownloaded: isTranscriptionModelDownloaded) else { return }
        coordinator.storedStage = OnboardingStage.experience.rawValue
        moveToExperienceStep(0, enhancementService: enhancementService)
    }

    func goToLicenseStep(isTranscriptionModelDownloaded: Bool) {
        guard coordinator.isReadyForExperience(isTranscriptionModelDownloaded: isTranscriptionModelDownloaded) else { return }
        coordinator.storedStage = OnboardingStage.license.rawValue
    }

    func goToContextAwarenessStep(isTranscriptionModelDownloaded: Bool) {
        guard coordinator.isReadyForExperience(isTranscriptionModelDownloaded: isTranscriptionModelDownloaded),
              coordinator.shouldShowContextAwarenessAfterCurrentExperience else {
            return
        }

        activateCleanTranscriptionMode()
        coordinator.storedStage = OnboardingStage.contextAwareness.rawValue
    }

    func goToTrustStep(isTranscriptionModelDownloaded: Bool) {
        guard coordinator.isReadyForExperience(isTranscriptionModelDownloaded: isTranscriptionModelDownloaded) else { return }
        coordinator.storedStage = OnboardingStage.trust.rawValue
    }

    func requestSkipAPISetup() {
        coordinator.isShowingSkipAPISetupWarning = true
    }

    func skipAPISetupAndContinue(
        isTranscriptionModelDownloaded: Bool,
        enhancementService: AIEnhancementService
    ) {
        coordinator.hasSkippedAPISetup = true
        coordinator.isSelectedAPIProviderVerified = false
        goToExperienceStep(
            isTranscriptionModelDownloaded: isTranscriptionModelDownloaded,
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
        isTranscriptionModelDownloaded: Bool,
        enhancementService: AIEnhancementService
    ) {
        guard coordinator.isReadyForExperience(isTranscriptionModelDownloaded: isTranscriptionModelDownloaded) else {
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

    func goToPreviousLicenseStep(isTranscriptionModelDownloaded: Bool) {
        guard coordinator.isReadyForExperience(isTranscriptionModelDownloaded: isTranscriptionModelDownloaded) else {
            coordinator.storedStage = OnboardingStage.api.rawValue
            return
        }

        coordinator.storedStage = OnboardingStage.trust.rawValue
    }

    func advanceExperienceStep(
        isTranscriptionModelDownloaded: Bool,
        enhancementService: AIEnhancementService
    ) {
        guard coordinator.isCurrentExperienceReady(isTranscriptionModelDownloaded: isTranscriptionModelDownloaded) else {
            return
        }

        if coordinator.shouldShowContextAwarenessAfterCurrentExperience {
            goToContextAwarenessStep(isTranscriptionModelDownloaded: isTranscriptionModelDownloaded)
        } else if coordinator.isLastExperienceStep {
            goToTrustStep(isTranscriptionModelDownloaded: isTranscriptionModelDownloaded)
        } else {
            moveToExperienceStep(
                coordinator.normalizedExperienceStepIndex + 1,
                enhancementService: enhancementService
            )
        }
    }

    func startLicenseTrial(
        isTranscriptionModelDownloaded: Bool,
        onComplete: () -> Void
    ) {
        coordinator.licenseViewModel.startTrial()
        completeOnboarding(
            isTranscriptionModelDownloaded: isTranscriptionModelDownloaded,
            onComplete: onComplete
        )
    }

    func activateLicense() {
        Task { @MainActor in
            await coordinator.licenseViewModel.validateLicense()
        }
    }

    func reconcileStage(
        isTranscriptionModelDownloaded: Bool,
        enhancementService: AIEnhancementService
    ) {
        if coordinator.stage == .microphone && !coordinator.requiredPermissionsGranted {
            goToPermissionsStep()
        }

        if coordinator.stage == .model &&
            (!coordinator.requiredPermissionsGranted || !coordinator.hasSelectedOnboardingMicrophone) {
            goToFirstIncompleteSetupStep(isTranscriptionModelDownloaded: isTranscriptionModelDownloaded)
        }

        if coordinator.stage == .api &&
            (!coordinator.requiredPermissionsGranted ||
             !coordinator.hasSelectedOnboardingMicrophone ||
             !isTranscriptionModelDownloaded) {
            goToFirstIncompleteSetupStep(isTranscriptionModelDownloaded: isTranscriptionModelDownloaded)
        }

        if (coordinator.stage == .experience ||
            coordinator.stage == .contextAwareness ||
            coordinator.stage == .trust ||
            coordinator.stage == .license) &&
            !coordinator.isReadyForExperience(isTranscriptionModelDownloaded: isTranscriptionModelDownloaded) {
            goToFirstIncompleteSetupStep(isTranscriptionModelDownloaded: isTranscriptionModelDownloaded)
        }

        if coordinator.stage == .experience &&
            coordinator.isReadyForExperience(isTranscriptionModelDownloaded: isTranscriptionModelDownloaded) &&
            !coordinator.isExperienceModeInstalled {
            installCurrentExperienceMode(enhancementService: enhancementService)
        }

        if coordinator.stage == .contextAwareness &&
            coordinator.isReadyForExperience(isTranscriptionModelDownloaded: isTranscriptionModelDownloaded) {
            activateCleanTranscriptionMode()
        }
    }

    func goToFirstIncompleteSetupStep(isTranscriptionModelDownloaded: Bool) {
        if !coordinator.requiredPermissionsGranted {
            coordinator.storedStage = OnboardingStage.permissions.rawValue
        } else if !coordinator.hasSelectedOnboardingMicrophone {
            coordinator.storedStage = OnboardingStage.microphone.rawValue
        } else if !isTranscriptionModelDownloaded {
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
              !modelManager.isFluidAudioModelDownloading(model) else {
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
        isTranscriptionModelDownloaded: Bool,
        onComplete: () -> Void
    ) {
        guard coordinator.stage == .license ||
                coordinator.isCurrentExperienceReady(isTranscriptionModelDownloaded: isTranscriptionModelDownloaded) else {
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

    func ensureDefaultOnboardingProvider() {
        if let storedProvider = AIProvider(rawValue: coordinator.storedOnboardingAIProvider),
           coordinator.onboardingProviderOptions.contains(storedProvider) {
            return
        }

        let defaultProvider: AIProvider = coordinator.onboardingProviderOptions.contains(.groq)
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
            modelName: coordinator.selectedOnboardingProvider.defaultModel
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
            StarterModeFactory.isInstalled(kind: coordinator.experienceModeTemplate.kind) &&
            hasRequiredPrompts
        coordinator.hasExperienceModeShortcut = ShortcutStore.shortcut(for: coordinator.experienceShortcutAction) != nil
    }

    func clearExperienceShortcutForIntroIfNeeded() {
        guard coordinator.stage == .experience,
              coordinator.isExperienceInIntroPhase,
              coordinator.experienceStep.shouldClearShortcutOnIntro,
              !coordinator.clearedExperienceShortcutActions.contains(coordinator.experienceShortcutAction) else {
            return
        }

        var clearedActions = coordinator.clearedExperienceShortcutActions
        clearedActions.insert(coordinator.experienceShortcutAction)
        coordinator.clearedExperienceShortcutActions = clearedActions
        ShortcutStore.setShortcut(nil, for: coordinator.experienceShortcutAction)
    }

    func activateExperienceModeForDemo() {
        guard coordinator.stage == .experience,
              let config = ModeManager.shared.getConfiguration(with: coordinator.experienceModeTemplate.id) else {
            return
        }

        applyDefaultMode(for: coordinator.experienceStep)
        ModeManager.shared.setActiveConfiguration(config)
    }

    func activateCleanTranscriptionMode() {
        guard let cleanTemplate = StarterModeCatalog.templates.first(where: { $0.kind == .clean }),
              let cleanConfig = ModeManager.shared.getConfiguration(with: cleanTemplate.id) else {
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
              ModeManager.shared.getDefaultConfiguration()?.id != template.id else {
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
