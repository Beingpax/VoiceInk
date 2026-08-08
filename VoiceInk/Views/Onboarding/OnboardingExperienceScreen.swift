import SwiftUI

struct OnboardingExperienceScreen: View {
    let step: OnboardingExperienceStep
    let isInIntroPhase: Bool
    let shortcutAction: ShortcutAction
    let hasShortcut: Bool
    @Binding var text: String
    let isLastStep: Bool
    let isReady: Bool
    let isComplete: Bool
    let onBackFromIntro: () -> Void
    let onContinueIntro: () -> Void
    let onBackFromPractice: () -> Void
    let onAdvance: () -> Void
    let onShortcutChanged: () -> Void
    let onAppear: () -> Void

    var body: some View {
        Group {
            if isInIntroPhase {
                introScreen
                    .transition(.opacity)
            } else {
                practiceScreen
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isInIntroPhase)
        .onAppear(perform: onAppear)
    }

    private var introScreen: some View {
        OnboardingStepScreen(
            systemImage: systemImage,
            title: step.title,
            subtitle: step.subtitle,
            contentMaxWidth: 560,
            showsHeader: true
        ) {
            OnboardingExperienceIntroCard(
                step: step,
                shortcutAction: shortcutAction,
                hasShortcut: hasShortcut,
                onShortcutChanged: onShortcutChanged
            )
            .id(step.id)
        } bottomBar: {
            OnboardingBottomBar(
                leadingTitle: "Back",
                primaryTitle: "Continue",
                isPrimaryEnabled: hasShortcut,
                onLeading: onBackFromIntro,
                onPrimary: onContinueIntro
            )
        }
    }

    private var practiceScreen: some View {
        OnboardingStepScreen(
            systemImage: systemImage,
            title: step.title,
            subtitle: step.subtitle,
            contentMaxWidth: 700,
            showsHeader: true
        ) {
            OnboardingExperienceCard(
                step: step,
                shortcutAction: shortcutAction,
                hasShortcut: hasShortcut,
                text: $text,
                onShortcutChanged: onShortcutChanged
            )
        } bottomBar: {
            OnboardingBottomBar(
                leadingTitle: "Back",
                primaryTitle: isLastStep ? "Continue" : "Next",
                isPrimaryEnabled: isReady && isComplete,
                onLeading: onBackFromPractice,
                onPrimary: onAdvance
            )
        }
    }

    private var systemImage: String {
        step.systemImage
    }
}
