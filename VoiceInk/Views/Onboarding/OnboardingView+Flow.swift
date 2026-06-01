import Foundation

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
        experienceStepIndex = 0
        installExperienceMode(at: 0)
        storedStage = OnboardingStage.experience.rawValue
        activateExperienceModeForDemo()
        refreshExperienceModeState()
    }

    func goToPreviousExperienceStep() {
        if normalizedExperienceStepIndex > 0 {
            experienceStepIndex = normalizedExperienceStepIndex - 1
        } else {
            storedStage = OnboardingStage.api.rawValue
        }
    }

    func advanceExperienceStep() {
        guard isCurrentExperienceReady else { return }

        if isLastExperienceStep {
            completeOnboarding()
        } else {
            let nextIndex = normalizedExperienceStepIndex + 1
            installExperienceMode(at: nextIndex)
            experienceStepIndex = nextIndex
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

        let installedKinds = OnboardingExperienceCatalog.steps
            .prefix(index + 1)
            .map(\.starterModeKind)

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
        refreshExperienceModeState()
    }

    func installCurrentExperienceMode() {
        guard stage == .experience else { return }
        installExperienceMode(at: normalizedExperienceStepIndex)
    }

    func installCurrentExperienceModeIfNeeded() {
        guard stage == .experience, !isExperienceModeInstalled else { return }
        installCurrentExperienceMode()
    }

    func refreshExperienceModeState() {
        let hasRequiredPrompts = StarterModePromptSeeder.hasPrompts(
            for: [experienceModeTemplate.kind],
            in: enhancementService.customPrompts
        )

        isExperienceModeInstalled = StarterModeFactory.isInstalled(kind: experienceModeTemplate.kind) && hasRequiredPrompts
        hasExperienceModeShortcut = ShortcutStore.shortcut(for: experienceShortcutAction) != nil
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
}
