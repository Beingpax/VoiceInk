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

    func goToModelStep() {
        guard coordinator.requiredPermissionsGranted else { return }
        coordinator.storedStage = OnboardingStage.model.rawValue
    }

    func goToAPIStep(
        isTranscriptionModelDownloaded: Bool,
        aiService: AIService
    ) {
        guard coordinator.requiredPermissionsGranted, isTranscriptionModelDownloaded else { return }
        ensureDefaultOnboardingProvider()
        selectOnboardingProvider(coordinator.selectedOnboardingProvider, aiService: aiService)
        coordinator.storedStage = OnboardingStage.api.rawValue
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
        withAnimation(.easeInOut(duration: 0.28)) {
            coordinator.isExperienceInIntroPhase = true
        }
    }

    func goToPreviousExperienceStep(enhancementService: AIEnhancementService) {
        if coordinator.normalizedExperienceStepIndex > 0 {
            moveToExperienceStep(
                coordinator.normalizedExperienceStepIndex - 1,
                enhancementService: enhancementService
            )
        } else {
            coordinator.storedStage = OnboardingStage.api.rawValue
        }
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

        if coordinator.isLastExperienceStep {
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
        if coordinator.stage == .model && !coordinator.requiredPermissionsGranted {
            goToPermissionsStep()
        }

        if coordinator.stage == .api && (!coordinator.requiredPermissionsGranted || !isTranscriptionModelDownloaded) {
            goToFirstIncompleteSetupStep(isTranscriptionModelDownloaded: isTranscriptionModelDownloaded)
        }

        if (coordinator.stage == .experience || coordinator.stage == .trust || coordinator.stage == .license) &&
            !coordinator.isReadyForExperience(isTranscriptionModelDownloaded: isTranscriptionModelDownloaded) {
            goToFirstIncompleteSetupStep(isTranscriptionModelDownloaded: isTranscriptionModelDownloaded)
        }

        if coordinator.stage == .experience &&
            coordinator.isReadyForExperience(isTranscriptionModelDownloaded: isTranscriptionModelDownloaded) &&
            !coordinator.isExperienceModeInstalled {
            installCurrentExperienceMode(enhancementService: enhancementService)
        }
    }

    func goToFirstIncompleteSetupStep(isTranscriptionModelDownloaded: Bool) {
        if !coordinator.requiredPermissionsGranted {
            coordinator.storedStage = OnboardingStage.permissions.rawValue
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
        coordinator.isExperienceInIntroPhase = true
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
              coordinator.experienceStep.kind != .rewriteFormat,
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

        ModeManager.shared.setActiveConfiguration(config)
    }

    func activateCleanTranscriptionMode() {
        guard let cleanTemplate = StarterModeCatalog.templates.first(where: { $0.kind == .clean }),
              let cleanConfig = ModeManager.shared.getConfiguration(with: cleanTemplate.id) else {
            return
        }

        ModeManager.shared.setActiveConfiguration(cleanConfig)
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
