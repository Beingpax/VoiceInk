import SwiftUI

struct TranscriptionModelDownloadCard: View {
    let model: FluidAudioModel
    let isDownloaded: Bool
    let isDownloading: Bool
    let status: FluidAudioDownloadStatus?
    let onDownload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            modelMetadata

            if let status {
                progressPanel(status)
            }
        }
        .padding(18)
        .background(AppMaterialCardBackground(cornerRadius: 12))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                modelLogo

                VStack(alignment: .leading, spacing: 6) {
                    Text(model.displayName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(AppTheme.Text.primary)

                    Text("Fast multilingual transcription that runs locally on Mac.")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.Text.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.92)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            statusControl
        }
    }

    @ViewBuilder
    private var statusControl: some View {
        if isDownloading {
            downloadButton
                .fixedSize()
        } else if isDownloaded {
            statusBadge
                .fixedSize()
        } else {
            downloadButton
                .fixedSize()
        }
    }

    private var modelLogo: some View {
        Image("nvidia-logo")
            .resizable()
            .scaledToFit()
            .frame(width: 34, height: 28)
            .frame(width: 38, height: 38)
            .accessibilityLabel("NVIDIA")
    }

    private var modelMetadata: some View {
        HStack(spacing: 6) {
            metadataPill(model.size)
            metadataPill("25+ languages")
            metadataPill("Local")
        }
    }

    private func metadataPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(AppTheme.Text.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(AppTheme.Surface.subtle))
    }

    private func progressPanel(_ status: FluidAudioDownloadStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(status.message)
                    .lineLimit(1)

                Spacer()

                Text("\(Int(status.fractionCompleted * 100))%")
                    .fontDesign(.monospaced)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(AppTheme.Text.secondary)

            ProgressView(value: status.fractionCompleted)
                .progressViewStyle(.linear)
                .tint(AppTheme.Accent.primary)
        }
        .animation(.smooth, value: status.fractionCompleted)
    }

    private var downloadButton: some View {
        Button(action: onDownload) {
            HStack(spacing: 6) {
                if isDownloading {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(downloadButtonTitle)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(canDownload ? AppTheme.Action.primaryForeground : AppTheme.Action.disabledForeground)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(canDownload ? AppTheme.Action.primaryFill : AppTheme.Action.disabledFill)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canDownload)
    }

    private var statusBadge: some View {
        Text("Downloaded")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(AppTheme.Text.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(AppTheme.Surface.controlActive))
    }

    private var downloadButtonTitle: String {
        if isDownloading {
            return "Downloading..."
        }

        if status != nil {
            return "Resume Download"
        }

        return "Download Model"
    }

    private var canDownload: Bool {
        !isDownloading
    }
}
