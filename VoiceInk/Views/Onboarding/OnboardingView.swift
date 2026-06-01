import SwiftUI
import AppKit

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject var engine: VoiceInkEngine
    @EnvironmentObject var fluidAudioModelManager: FluidAudioModelManager
    @EnvironmentObject var aiService: AIService
    @EnvironmentObject var enhancementService: AIEnhancementService

    @AppStorage("onboardingStage") var storedStage = OnboardingStage.permissions.rawValue
    @AppStorage("onboardingActivePermission") var storedActivePermission = OnboardingPermissionKind.microphone.rawValue
    @AppStorage("onboardingRequestedScreenRecording") var hasRequestedScreenRecording = false
    @AppStorage("onboardingExperienceIndex") var experienceStepIndex = 0

    @State var permissionStatuses: [OnboardingPermissionKind: OnboardingPermissionStatus] = [:]
    @State var refreshTask: Task<Void, Never>?
    @State var isSelectedAPIProviderVerified = false
    @State var hasExperienceModeShortcut = false
    @State var isExperienceModeInstalled = false
    @State var experienceTextByKind: [OnboardingExperienceKind: String] = [:]

    let contentMaxWidth: CGFloat = 560

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
        OnboardingPermissionKind.required.allSatisfy { status(for: $0).isGranted }
    }

    var currentStepNumber: Int {
        if stage == .experience {
            return OnboardingStage.baseStepCount + normalizedExperienceStepIndex + 1
        }

        return stage.stepNumber
    }

    var totalStepCount: Int {
        OnboardingStage.baseStepCount + OnboardingExperienceCatalog.steps.count
    }

    var experienceStep: OnboardingExperienceStep {
        OnboardingExperienceCatalog.steps[safe: normalizedExperienceStepIndex] ?? OnboardingExperienceCatalog.steps[0]
    }

    var experienceModeTemplate: StarterModeTemplate {
        StarterModeCatalog.templates.first { $0.kind == experienceStep.starterModeKind } ?? StarterModeCatalog.templates[0]
    }

    var normalizedExperienceStepIndex: Int {
        min(max(experienceStepIndex, 0), max(OnboardingExperienceCatalog.steps.count - 1, 0))
    }

    var isLastExperienceStep: Bool {
        normalizedExperienceStepIndex == OnboardingExperienceCatalog.steps.count - 1
    }

    var experienceShortcutAction: ShortcutAction {
        if experienceStep.kind == .dictation {
            return .primaryRecording
        }

        return .mode(experienceModeTemplate.id)
    }

    var experienceShortcutLabel: String {
        ShortcutStore.shortcut(for: experienceShortcutAction)?.displayString ?? "the shortcut"
    }

    var experienceDefaultShortcut: Shortcut? {
        switch experienceStep.kind {
        case .dictation:
            return nil
        case .enhance, .enhanceAgain:
            return .rightCommand
        case .rewrite, .rewriteFormat:
            return nil
        case .respond:
            return nil
        }
    }

    var currentExperienceText: Binding<String> {
        Binding(
            get: {
                experienceTextByKind[experienceStep.kind] ?? experienceStep.initialFieldText
            },
            set: { newValue in
                experienceTextByKind[experienceStep.kind] = newValue
            }
        )
    }

    var isCurrentExperienceComplete: Bool {
        if experienceStep.kind == .respond {
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

    var isReadyForExperience: Bool {
        requiredPermissionsGranted &&
            isTranscriptionModelDownloaded &&
            isSelectedAPIProviderVerified
    }

    var isCurrentExperienceReady: Bool {
        isReadyForExperience &&
            isExperienceModeInstalled &&
            hasExperienceModeShortcut
    }

    var selectedOnboardingProvider: AIProvider {
        .groq
    }

    var requiredTranscriptionModel: FluidAudioModel? {
        TranscriptionModelRegistry.models
            .compactMap { $0 as? FluidAudioModel }
            .first { $0.name == "parakeet-tdt-0.6b-v3" }
    }

    var isTranscriptionModelDownloaded: Bool {
        guard let requiredTranscriptionModel else { return false }
        return fluidAudioModelManager.isFluidAudioModelDownloaded(requiredTranscriptionModel)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            OnboardingBackground()

            Group {
                switch stage {
                case .permissions:
                    permissionsScreen
                        .transition(.opacity)
                case .model:
                    modelScreen
                        .transition(.opacity)
                case .api:
                    apiScreen
                        .transition(.opacity)
                case .experience:
                    experienceScreen
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            OnboardingProgressBadge(
                currentStep: currentStepNumber,
                totalSteps: totalStepCount
            )
            .padding(.leading, 28)
            .padding(.bottom, 26)
            .allowsHitTesting(false)
        }
        .frame(minWidth: 820, minHeight: 680)
        .animation(.easeInOut(duration: 0.22), value: stage)
        .onAppear {
            refreshPermissionStatuses()
            refreshAPIVerification()
            refreshExperienceModeState()
            reconcileStage()
        }
        .onDisappear {
            refreshTask?.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionStatuses()
            reconcileStage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiProviderKeyChanged)) { _ in
            refreshAPIVerification()
        }
        .onReceive(NotificationCenter.default.publisher(for: ShortcutStore.shortcutDidChange)) { notification in
            guard let action = notification.object as? ShortcutAction, action == experienceShortcutAction else { return }
            refreshExperienceModeState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .modeConfigurationsDidChange)) { _ in
            refreshExperienceModeState()
        }
        .onChange(of: experienceStepIndex) { _, _ in
            installCurrentExperienceMode()
            activateExperienceModeForDemo()
            refreshExperienceModeState()
        }
        .onChange(of: storedStage) { _, _ in
            installCurrentExperienceModeIfNeeded()
            activateExperienceModeForDemo()
            refreshExperienceModeState()
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
}
