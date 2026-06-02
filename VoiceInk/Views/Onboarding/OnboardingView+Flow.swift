import Foundation
import SwiftUI

extension OnboardingView {
    func goToPermissionsStep() {
        storedStage = OnboardingStage.permissions.rawValue
    }

    func goToModelStep() {
        guard requiredPermissionsGranted else { return }
        storedStage = OnboardingStage.model.rawValue
    }

    func goToAPIStep() {
        guard requiredPermissionsGranted, isTranscriptionModelDownloaded else { return }
        storedStage = OnboardingStage.api.rawValue
    }

    func goToExperienceStep() {
        guard isReadyForExperience else { return }
        storedStage = OnboardingStage.experience.rawValue
        moveToExperienceStep(0)
    }

    func goToExperiencePracticePhase() {
        withAnimation(.easeInOut(duration: 0.28)) {
            isExperienceInIntroPhase = false
        }
    }

    func goToExperienceIntroPhase() {
        withAnimation(.easeInOut(duration: 0.28)) {
            isExperienceInIntroPhase = true
        }
    }

    func goToPreviousExperienceStep() {
        if normalizedExperienceStepIndex > 0 {
            moveToExperienceStep(normalizedExperienceStepIndex - 1)
        } else {
            storedStage = OnboardingStage.api.rawValue
        }
    }

    func advanceExperienceStep() {
        guard isCurrentExperienceReady else { return }

        if isLastExperienceStep {
            completeOnboarding()
        } else {
            moveToExperienceStep(normalizedExperienceStepIndex + 1)
        }
    }

    func reconcileStage() {
        if stage == .model && !requiredPermissionsGranted {
            goToPermissionsStep()
        }

        if stage == .api && (!requiredPermissionsGranted || !isTranscriptionModelDownloaded) {
            storedStage = requiredPermissionsGranted ? OnboardingStage.model.rawValue : OnboardingStage.permissions.rawValue
        }

        if stage == .experience && !isReadyForExperience {
            if !requiredPermissionsGranted {
                storedStage = OnboardingStage.permissions.rawValue
            } else if !isTranscriptionModelDownloaded {
                storedStage = OnboardingStage.model.rawValue
            } else {
                storedStage = OnboardingStage.api.rawValue
            }
        }

        if stage == .experience && isReadyForExperience && !isExperienceModeInstalled {
            installCurrentExperienceMode()
        }
    }

    func downloadTranscriptionModel(_ model: FluidAudioModel) {
        guard requiredPermissionsGranted,
              !fluidAudioModelManager.isFluidAudioModelDownloaded(model),
              !fluidAudioModelManager.isFluidAudioModelDownloading(model) else {
            return
        }

        Task {
            await fluidAudioModelManager.downloadFluidAudioModel(model)
        }
    }

    func moveToExperienceStep(_ index: Int) {
        guard OnboardingExperienceCatalog.steps.indices.contains(index) else {
            return
        }

        experienceStepIndex = index
        isExperienceInIntroPhase = true
        resetExperienceText(at: index)
        installExperienceMode(at: index)
        activateExperienceModeForDemo()
        clearExperienceShortcutForIntroIfNeeded()
        refreshExperienceModeState()
    }

    func completeOnboarding() {
        guard isCurrentExperienceReady else { return }

        UserDefaults.standard.removeObject(forKey: "onboardingStage")
        UserDefaults.standard.removeObject(forKey: "onboardingActivePermission")
        UserDefaults.standard.removeObject(forKey: "onboardingRequestedScreenRecording")
        UserDefaults.standard.removeObject(forKey: "onboardingAIProvider")
        UserDefaults.standard.removeObject(forKey: "onboardingExperienceIndex")
        UserDefaults.standard.removeObject(forKey: "onboardingStarterModeIndex")
        activateCleanTranscriptionMode()
        hasCompletedOnboarding = true
    }

    func refreshAPIVerification() {
        isSelectedAPIProviderVerified = APIKeyManager.shared.hasAPIKey(
            forProvider: selectedOnboardingProvider.rawValue
        )
    }

    func installExperienceMode(at index: Int) {
        guard OnboardingExperienceCatalog.steps.indices.contains(index) else {
            return
        }

        var seenKinds = Set<StarterModeKind>()
        let installedKinds = OnboardingExperienceCatalog.steps
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
            provider: selectedOnboardingProvider,
            modelName: aiService.selectedModel(for: selectedOnboardingProvider)
        )
    }

    func installCurrentExperienceMode() {
        guard stage == .experience else { return }
        installExperienceMode(at: normalizedExperienceStepIndex)
        refreshExperienceModeState()
    }

    func refreshExperienceModeState() {
        let hasRequiredPrompts = StarterModePromptSeeder.hasPrompts(
            for: [experienceModeTemplate.kind],
            in: enhancementService.customPrompts
        )

        isExperienceModeInstalled = StarterModeFactory.isInstalled(kind: experienceModeTemplate.kind) && hasRequiredPrompts
        hasExperienceModeShortcut = ShortcutStore.shortcut(for: experienceShortcutAction) != nil
    }

    func clearExperienceShortcutForIntroIfNeeded() {
        guard stage == .experience,
              isExperienceInIntroPhase,
              experienceStep.kind != .rewriteFormat,
              !clearedExperienceShortcutActions.contains(experienceShortcutAction) else {
            return
        }

        clearedExperienceShortcutActions.insert(experienceShortcutAction)
        ShortcutStore.setShortcut(nil, for: experienceShortcutAction)
    }

    func activateExperienceModeForDemo() {
        guard stage == .experience,
              let config = ModeManager.shared.getConfiguration(with: experienceModeTemplate.id) else {
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
        guard let step = OnboardingExperienceCatalog.steps[safe: index] else {
            return
        }

        experienceTextByKind[step.kind] = step.initialFieldText
    }
}
