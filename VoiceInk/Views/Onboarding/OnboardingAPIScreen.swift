import SwiftUI

struct OnboardingAPIScreen: View {
    @ObservedObject var aiService: AIService

    let contentMaxWidth: CGFloat
    let providerOptions: [AIProvider]
    @Binding var selectedProvider: AIProvider
    let isSelectedProviderVerified: Bool
    let canContinue: Bool
    @Binding var isShowingSkipWarning: Bool
    let onVerificationChanged: () -> Void
    let onBack: () -> Void
    let onContinue: () -> Void
    let onRequestSkip: () -> Void
    let onConfirmSkip: () -> Void

    var body: some View {
        OnboardingStepScreen(
            stage: .api,
            contentMaxWidth: contentMaxWidth
        ) {
            VStack(spacing: 14) {
                AIProviderVerificationCard(
                    aiService: aiService,
                    providerOptions: providerOptions,
                    selectedProvider: $selectedProvider,
                    onVerificationChanged: onVerificationChanged
                )

                if !isSelectedProviderVerified {
                    skipAPISetupButton
                }
            }
        } bottomBar: {
            OnboardingBottomBar(
                leadingTitle: "Back",
                primaryTitle: "Continue",
                isPrimaryEnabled: canContinue,
                onLeading: onBack,
                onPrimary: onContinue
            )
        }
        .alert("Skip API setup?", isPresented: $isShowingSkipWarning) {
            Button("Cancel", role: .cancel) { }
            Button("Skip API setup", role: .destructive) {
                onConfirmSkip()
            }
        } message: {
            Text("VoiceInk will skip API setup during onboarding. Most enhancement and AI-related features will not work without an API key. You can always set it up later in the app.")
        }
    }

    private var skipAPISetupButton: some View {
        Button(action: onRequestSkip) {
            Text("Skip API setup")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.Text.muted)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(AppTheme.Surface.subtle)
                )
        }
        .buttonStyle(.plain)
        .help("Continue with local dictation only")
    }
}
