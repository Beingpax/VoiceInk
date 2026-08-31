import SwiftUI

struct OnboardingShortcutSetupView: View {
    let action: ShortcutAction
    let onShortcutChanged: () -> Void

    var body: some View {
        ShortcutRecorder(
            action: action,
            onShortcutChanged: onShortcutChanged
        )
        .fixedSize(horizontal: true, vertical: false)
        .onChange(of: action) { _, _ in
            onShortcutChanged()
        }
    }
}
