import AppKit
import SwiftUI

struct VoiceInkRefineModelCardView: View {
    @EnvironmentObject private var aiService: AIService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDeleteConfirmationPresented = false

    private let modelID = VoiceInkRefineService.defaultModel
    private let sourceURL = URL(
        string: "https://huggingface.co/beingpax/voiceink-refine-v1"
    )!

    private var storageInfo: VoiceInkRefineModelStorageInfo {
        aiService.voiceInkRefineStorageInfo(for: modelID)
    }

    private var downloadProgress: Double? {
        aiService.voiceInkRefineDownloadProgress[modelID]
    }

    private var isDownloading: Bool {
        downloadProgress != nil
    }

    private var downloadError: String? {
        aiService.voiceInkRefineDownloadErrors[modelID]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                headerSection
                metadataSection
                descriptionSection
                progressSection
                errorSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actionSection
        }
        .padding(16)
        .background(AppMaterialCardBackground())
        .confirmationDialog(
            "Delete VoiceInk Refine?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Model", role: .destructive) {
                Task { @MainActor in
                    await aiService.deleteVoiceInkRefineModel(modelID)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the downloaded model from this Mac. You can download it again later.")
        }
    }

    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(VoiceInkRefineService.model.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(.labelColor))

            Text("Enhancement")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(AppTheme.Surface.controlActive))

            Spacer()
        }
    }

    private var metadataSection: some View {
        HStack(spacing: 12) {
            Label("On-device", systemImage: "cpu")

            if storageInfo.isDownloaded, storageInfo.sizeInBytes > 0 {
                Label(
                    Self.byteFormatter.string(fromByteCount: storageInfo.sizeInBytes),
                    systemImage: "internaldrive"
                )
            }

            Link(destination: sourceURL) {
                Label("Hugging Face", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 11))
        .foregroundColor(Color(.secondaryLabelColor))
        .lineLimit(1)
    }

    private var descriptionSection: some View {
        Text(VoiceInkRefineService.model.detail)
            .font(.system(size: 11))
            .foregroundColor(Color(.secondaryLabelColor))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    @ViewBuilder
    private var progressSection: some View {
        if let downloadProgress {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(downloadProgress > 0 ? "Downloading model files" : "Preparing download")
                        .lineLimit(1)

                    if downloadProgress <= 0 {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.65)
                    }

                    Spacer()

                    Text(downloadProgress, format: .percent.precision(.fractionLength(0)))
                        .fontDesign(.monospaced)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(.secondaryLabelColor))

                ProgressView(value: downloadProgress)
                    .progressViewStyle(.linear)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .animation(reduceMotion ? nil : .smooth, value: downloadProgress)
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let downloadError {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(downloadError)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 11))
            .foregroundStyle(AppTheme.Status.error)
            .padding(.top, 6)
        }
    }

    private var actionSection: some View {
        HStack(spacing: 8) {
            if storageInfo.isDownloaded && !isDownloading {
                if storageInfo.isLoaded {
                    modelStatusPill("Loaded", systemImage: "memorychip.fill")
                } else {
                    modelStatusPill("Downloaded", systemImage: "checkmark.circle")
                }
            } else {
                Button {
                    Task { @MainActor in
                        await aiService.downloadVoiceInkRefineModel(modelID)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(isDownloading ? "Downloading..." : "Download")
                        Image(systemName: "arrow.down.circle")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(AppTheme.Accent.primary))
                }
                .buttonStyle(.plain)
                .disabled(isDownloading)
            }

            if storageInfo.isDownloaded && !isDownloading {
                Menu {
                    if storageInfo.isLoaded {
                        Button {
                            Task { @MainActor in
                                await aiService.unloadVoiceInkRefineModel()
                            }
                        } label: {
                            Label("Unload Model", systemImage: "memorychip")
                        }
                    }

                    Button {
                        if let modelDirectory = aiService.voiceInkRefineModelDirectory(for: modelID) {
                            NSWorkspace.shared.activateFileViewerSelecting([modelDirectory])
                        }
                    } label: {
                        Label("Show in Finder", systemImage: "folder")
                    }

                    Link(destination: sourceURL) {
                        Label("View on Hugging Face", systemImage: "arrow.up.right.square")
                    }

                    Divider()

                    Button(role: .destructive) {
                        isDeleteConfirmationPresented = true
                    } label: {
                        Label("Delete Model", systemImage: "trash")
                    }
                } label: {
                    Label("Model actions", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 14))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 20, height: 20)
            }
        }
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}
