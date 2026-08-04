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
            AIProviderVerificationCard(
                aiService: aiService,
                providerOptions: providerOptions,
                selectedProvider: $selectedProvider,
                onVerificationChanged: onVerificationChanged
            )
        } bottomBar: {
            OnboardingBottomBar(
                leadingTitle: "Back",
                primaryTitle: "Continue",
                isPrimaryEnabled: canContinue && isSelectedProviderVerified,
                onLeading: onBack,
                onPrimary: onContinue,
                skipTitle: isSelectedProviderVerified ? nil : "Skip This Step",
                onSkip: isSelectedProviderVerified ? nil : onRequestSkip
            )
        }
        .alert("Skip API setup?", isPresented: $isShowingSkipWarning) {
            Button("Cancel", role: .cancel) {}
            Button("Skip API setup", role: .destructive) {
                onConfirmSkip()
            }
        } message: {
            Text("Enhancement modes and AI actions will stay off. You can always set it up later in the app.")
        }
    }
}
