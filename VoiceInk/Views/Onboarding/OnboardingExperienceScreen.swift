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
            bottomBarMaxWidth: 560,
            showsHeader: true,
            contentYOffset: 24
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
            bottomBarMaxWidth: 700,
            showsHeader: true,
            contentYOffset: 38
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
                showsPrimaryButton: hasShortcut,
                onLeading: onBackFromPractice,
                onPrimary: onAdvance
            )
        }
    }

    private var systemImage: String {
        switch step.kind {
        case .dictation:
            return "text.cursor"
        case .enhance:
            return "sparkles"
        case .email:
            return "envelope.fill"
        case .rewrite, .rewriteFormat:
            return "quote.bubble.fill"
        case .respond:
            return "text.bubble.fill"
        }
    }
}
