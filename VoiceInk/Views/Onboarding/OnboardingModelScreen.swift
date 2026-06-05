import SwiftUI

struct OnboardingModelScreen: View {
    let contentMaxWidth: CGFloat
    let model: FluidAudioModel?
    let isDownloaded: Bool
    let isDownloading: Bool
    let downloadStatus: FluidAudioDownloadStatus?
    let onDownload: (FluidAudioModel) -> Void
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingStepScreen(
            stage: .model,
            contentMaxWidth: contentMaxWidth
        ) {
            if let model {
                TranscriptionModelDownloadCard(
                    model: model,
                    isDownloaded: isDownloaded,
                    isDownloading: isDownloading,
                    status: downloadStatus,
                    onDownload: {
                        onDownload(model)
                    }
                )
            }
        } bottomBar: {
            OnboardingBottomBar(
                leadingTitle: "Back",
                primaryTitle: "Continue",
                isPrimaryEnabled: isDownloaded && !isDownloading,
                onLeading: onBack,
                onPrimary: onContinue
            )
        }
    }
}
