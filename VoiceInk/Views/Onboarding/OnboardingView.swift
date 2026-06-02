import SwiftUI
import AppKit

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject var fluidAudioModelManager: FluidAudioModelManager
    @EnvironmentObject var aiService: AIService
    @EnvironmentObject var enhancementService: AIEnhancementService
    @StateObject private var coordinator = OnboardingCoordinator()

    let contentMaxWidth: CGFloat = 560

    var body: some View {
        let isTranscriptionModelDownloaded = coordinator.isTranscriptionModelDownloaded(
            using: fluidAudioModelManager
        )

        ZStack(alignment: .bottomLeading) {
            OnboardingBackground()

            Group {
                switch coordinator.stage {
                case .permissions:
                    OnboardingPermissionsScreen(
                        contentMaxWidth: contentMaxWidth,
                        isComplete: coordinator.requiredPermissionsGranted,
                        activePermission: coordinator.activePermission,
                        hasRequestedScreenRecording: coordinator.hasRequestedScreenRecording,
                        stepNumber: { coordinator.permissions.stepNumber(for: $0) },
                        status: { coordinator.permissions.status(for: $0) },
                        isLocked: { coordinator.permissions.isLocked($0) },
                        actionTitle: { coordinator.permissions.actionTitle(for: $0) },
                        onSelect: coordinator.permissions.setActivePermission,
                        onAction: coordinator.permissions.performAction,
                        onQuit: {
                            NSApplication.shared.terminate(nil)
                        },
                        onRecheck: coordinator.permissions.refreshPermissionStatuses,
                        onContinue: coordinator.flow.goToModelStep
                    )
                        .transition(.opacity)
                case .model:
                    OnboardingModelScreen(
                        contentMaxWidth: contentMaxWidth,
                        model: coordinator.requiredTranscriptionModel,
                        isDownloaded: isTranscriptionModelDownloaded,
                        isDownloading: coordinator.requiredTranscriptionModel.map {
                            fluidAudioModelManager.isFluidAudioModelDownloading($0)
                        } ?? false,
                        downloadStatus: coordinator.requiredTranscriptionModel.flatMap {
                            fluidAudioModelManager.downloadStatus(for: $0)
                        },
                        onDownload: {
                            coordinator.flow.downloadTranscriptionModel(
                                $0,
                                modelManager: fluidAudioModelManager
                            )
                        },
                        onBack: coordinator.flow.goToPermissionsStep,
                        onContinue: {
                            coordinator.flow.goToAPIStep(
                                isTranscriptionModelDownloaded: isTranscriptionModelDownloaded,
                                aiService: aiService
                            )
                        }
                    )
                        .transition(.opacity)
                case .api:
                    OnboardingAPIScreen(
                        aiService: aiService,
                        contentMaxWidth: contentMaxWidth,
                        providerOptions: coordinator.onboardingProviderOptions,
                        selectedProvider: coordinator.selectedOnboardingProviderBinding(aiService: aiService),
                        isSelectedProviderVerified: coordinator.isSelectedAPIProviderVerified,
                        canContinue: coordinator.isReadyForExperience(
                            isTranscriptionModelDownloaded: isTranscriptionModelDownloaded
                        ),
                        isShowingSkipWarning: $coordinator.isShowingSkipAPISetupWarning,
                        onVerificationChanged: coordinator.flow.refreshAPIVerification,
                        onBack: coordinator.flow.goToModelStep,
                        onContinue: {
                            coordinator.flow.goToExperienceStep(
                                isTranscriptionModelDownloaded: isTranscriptionModelDownloaded,
                                enhancementService: enhancementService
                            )
                        },
                        onRequestSkip: coordinator.flow.requestSkipAPISetup,
                        onConfirmSkip: {
                            coordinator.flow.skipAPISetupAndContinue(
                                isTranscriptionModelDownloaded: isTranscriptionModelDownloaded,
                                enhancementService: enhancementService
                            )
                        }
                    )
                        .transition(.opacity)
                case .experience:
                    OnboardingExperienceScreen(
                        step: coordinator.experienceStep,
                        isInIntroPhase: coordinator.isExperienceInIntroPhase,
                        shortcutAction: coordinator.experienceShortcutAction,
                        hasShortcut: coordinator.hasExperienceModeShortcut,
                        text: coordinator.currentExperienceText,
                        isLastStep: coordinator.isLastExperienceStep,
                        isReady: coordinator.isCurrentExperienceReady(
                            isTranscriptionModelDownloaded: isTranscriptionModelDownloaded
                        ),
                        isComplete: coordinator.isCurrentExperienceComplete,
                        onBackFromIntro: {
                            coordinator.flow.goToPreviousExperienceStep(enhancementService: enhancementService)
                        },
                        onContinueIntro: coordinator.flow.goToExperiencePracticePhase,
                        onBackFromPractice: coordinator.flow.goToExperienceIntroPhase,
                        onAdvance: {
                            coordinator.flow.advanceExperienceStep(
                                isTranscriptionModelDownloaded: isTranscriptionModelDownloaded,
                                enhancementService: enhancementService
                            )
                        },
                        onShortcutChanged: {
                            coordinator.flow.refreshExperienceModeState(enhancementService: enhancementService)
                        },
                        onAppear: coordinator.flow.activateExperienceModeForDemo
                    )
                        .transition(.opacity)
                case .license:
                    OnboardingLicenseScreen(
                        licenseViewModel: coordinator.licenseViewModel,
                        onBack: {
                            coordinator.flow.goToPreviousLicenseStep(
                                isTranscriptionModelDownloaded: isTranscriptionModelDownloaded,
                                enhancementService: enhancementService
                            )
                        },
                        onPurchase: {
                            coordinator.licenseViewModel.openPurchaseLink()
                        },
                        onStartTrial: {
                            coordinator.flow.startLicenseTrial(
                                isTranscriptionModelDownloaded: isTranscriptionModelDownloaded
                            ) {
                                hasCompletedOnboarding = true
                            }
                        },
                        onActivate: coordinator.flow.activateLicense,
                        onFinish: {
                            coordinator.flow.completeOnboarding(
                                isTranscriptionModelDownloaded: isTranscriptionModelDownloaded
                            ) {
                                hasCompletedOnboarding = true
                            }
                        }
                    )
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            OnboardingProgressBadge(
                currentStep: coordinator.currentStepNumber,
                totalSteps: coordinator.totalStepCount
            )
            .padding(.leading, 28)
            .padding(.bottom, 26)
            .allowsHitTesting(false)
        }
        .frame(minWidth: 820, minHeight: 680)
        .animation(.easeInOut(duration: 0.22), value: coordinator.stage)
        .onAppear {
            coordinator.flow.ensureDefaultOnboardingProvider()
            coordinator.permissions.refreshPermissionStatuses()
            coordinator.flow.refreshAPIVerification()
            coordinator.flow.refreshExperienceModeState(enhancementService: enhancementService)
            coordinator.flow.reconcileStage(
                isTranscriptionModelDownloaded: isTranscriptionModelDownloaded,
                enhancementService: enhancementService
            )
        }
        .onDisappear {
            coordinator.permissions.cancelRefreshTask()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            coordinator.permissions.refreshPermissionStatuses()
            coordinator.flow.reconcileStage(
                isTranscriptionModelDownloaded: isTranscriptionModelDownloaded,
                enhancementService: enhancementService
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiProviderKeyChanged)) { _ in
            coordinator.flow.refreshAPIVerification()
        }
        .onReceive(NotificationCenter.default.publisher(for: ShortcutStore.shortcutDidChange)) { notification in
            guard let action = notification.object as? ShortcutAction,
                  action == coordinator.experienceShortcutAction else {
                return
            }

            coordinator.flow.refreshExperienceModeState(enhancementService: enhancementService)
        }
        .onReceive(NotificationCenter.default.publisher(for: .modeConfigurationsDidChange)) { _ in
            coordinator.flow.refreshExperienceModeState(enhancementService: enhancementService)
        }
        .onChange(of: coordinator.stage) { _, _ in
            coordinator.flow.activateExperienceModeForDemo()
            coordinator.flow.refreshExperienceModeState(enhancementService: enhancementService)
        }
    }
}

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
}
