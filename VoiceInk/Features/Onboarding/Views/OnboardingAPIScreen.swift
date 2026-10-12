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
            HStack(spacing: 0) {
                Button(action: onBack) {
                    Text("Back")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.Action.secondaryForeground)
                        .frame(width: 132, height: 42)
                        .background(AppMaterialCardBackground(cornerRadius: AppTheme.Radius.control))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                if !isSelectedProviderVerified {
                    Button(action: onRequestSkip) {
                        Text("Set It Up Later")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppTheme.Text.secondary)
                            .padding(.horizontal, 4)
                            .frame(minHeight: 42)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .allowsTightening(true)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)

                Button(action: onContinue) {
                    Text("Continue")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(
                            canContinue && isSelectedProviderVerified
                                ? AppTheme.Action.primaryForeground : AppTheme.Action.disabledForeground
                        )
                        .padding(.horizontal, 20)
                        .frame(minWidth: 132, minHeight: 42)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                                .fill(
                                    canContinue && isSelectedProviderVerified
                                        ? AppTheme.Action.primaryFill : AppTheme.Action.disabledFill
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(!(canContinue && isSelectedProviderVerified))
            }
            .frame(maxWidth: OnboardingLayout.chromeMaxWidth)
        }
        .alert("Set up AI enhancement later?", isPresented: $isShowingSkipWarning) {
            Button("Go Back", role: .cancel) {}
            Button("Set It Up Later") {
                onConfirmSkip()
            }
        } message: {
            Text("Enhancement modes and AI actions will stay off until you add a key. You can set this up anytime from Settings.")
        }
    }
}
