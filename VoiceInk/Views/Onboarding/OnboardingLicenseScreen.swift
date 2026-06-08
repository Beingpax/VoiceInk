import SwiftUI

struct OnboardingLicenseScreen: View {
    @ObservedObject var licenseViewModel: LicenseViewModel

    let onBack: () -> Void
    let onPurchase: () -> Void
    let onStartTrial: () -> Void
    let onActivate: () -> Void
    let onFinish: () -> Void

    var body: some View {
        if case .licensed = licenseViewModel.licenseState {
            verificationSuccessScreen
        } else {
            setupScreen
        }
    }

    private var setupScreen: some View {
        OnboardingStepScreen(
            stage: .license,
            contentMaxWidth: 620
        ) {
            OnboardingLicenseSetupCard(
                licenseViewModel: licenseViewModel,
                onPurchase: onPurchase,
                onStartTrial: onStartTrial,
                onActivate: onActivate
            )
        } bottomBar: {
            OnboardingBottomBar(
                leadingTitle: "Back",
                primaryTitle: "Start 7-day Trial",
                isPrimaryEnabled: true,
                onLeading: onBack,
                onPrimary: onStartTrial
            )
        }
    }

    private var verificationSuccessScreen: some View {
        OnboardingStepScreen(
            systemImage: "checkmark.seal.fill",
            title: "Verification Successful",
            subtitle: "Your license key is verified. VoiceInk is ready to use on this Mac.",
            contentMaxWidth: 560
        ) {
            OnboardingVerifiedLicenseCard(
                licenseKey: licenseViewModel.licenseKey
            )
        } bottomBar: {
            OnboardingBottomBar(
                leadingTitle: nil,
                primaryTitle: "Finish Onboarding",
                isPrimaryEnabled: true,
                onLeading: nil,
                onPrimary: onFinish
            )
        }
    }
}
