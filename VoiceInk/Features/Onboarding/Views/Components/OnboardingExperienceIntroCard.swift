import SwiftUI

struct OnboardingExperienceIntroCard: View {
    let step: OnboardingExperienceStep
    let shortcutAction: ShortcutAction
    let hasShortcut: Bool
    let onShortcutChanged: () -> Void

    @State private var isVisible = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(introText))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AppTheme.Text.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsShortcutControl {
                OnboardingShortcutSetupView(
                    action: shortcutAction,
                    onShortcutChanged: onShortcutChanged
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .fixedSize(horizontal: false, vertical: false)
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.98)
        .offset(y: isVisible ? 0 : 10)
        .onAppear {
            isVisible = false
            withAnimation(.easeInOut(duration: 0.3).delay(0.08)) {
                isVisible = true
            }
        }
    }

    private var introText: String {
        if let shortcutIntroTitle = step.shortcutIntroTitle {
            return shortcutIntroTitle
        }

        return hasShortcut ? "Keyboard shortcut:" : "Choose a shortcut to get started."
    }

    private var showsShortcutControl: Bool {
        step.showsShortcutControl
    }
}
