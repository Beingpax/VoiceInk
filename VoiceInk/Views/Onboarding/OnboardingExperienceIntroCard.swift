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
                Text(introText)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsShortcutControl {
                OnboardingShortcutSetupView(
                    action: shortcutAction,
                    onShortcutChanged: onShortcutChanged
                )
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .fixedSize(horizontal: true, vertical: false)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.Surface.control.opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.Border.subtle, lineWidth: 1)
        )
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
        if step.kind == .rewriteFormat {
            return "Let's try it once again."
        }

        return hasShortcut ? "Keyboard shortcut:" : "Choose a shortcut to get started."
    }

    private var showsShortcutControl: Bool {
        step.kind != .rewriteFormat
    }
}
