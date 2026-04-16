import SwiftUI
import Combine
import AppKit

struct FluidAudioModelCardRowView: View {
    let model: FluidAudioModel
    @ObservedObject var fluidAudioModelManager: FluidAudioModelManager
    @ObservedObject var transcriptionModelManager: TranscriptionModelManager
    @State private var streamingEnabled = true

    private var streamingDefaultsKey: String {
        "streaming-enabled-\(model.name)"
    }

    var isCurrent: Bool {
        transcriptionModelManager.currentTranscriptionModel?.name == model.name
    }

    var isDownloaded: Bool {
        fluidAudioModelManager.isFluidAudioModelDownloaded(model)
    }

    var isDownloading: Bool {
        fluidAudioModelManager.isFluidAudioModelDownloading(model)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                headerSection
                metadataSection
                descriptionSection
                progressSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actionSection
        }
        .padding(16)
        .background(CardBackground(isSelected: isCurrent, useAccentGradientWhenSelected: isCurrent))
        .onAppear {
            streamingEnabled = UserDefaults.standard.object(forKey: streamingDefaultsKey) as? Bool ?? true
        }
    }

    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(.labelColor))

            statusBadge

            if model.supportsStreaming && isDownloaded {
                streamingModeBadge
            }

            Spacer()
        }
    }

    private var streamingModeBadge: some View {
        Button {
            streamingEnabled.toggle()
            UserDefaults.standard.set(streamingEnabled, forKey: streamingDefaultsKey)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: streamingEnabled ? "waveform" : "doc.text")
                    .font(.system(size: 8, weight: .semibold))
                Text(streamingEnabled ? "Live" : "Batch")
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(streamingEnabled
                    ? Color.accentColor.opacity(0.15)
                    : Color(.secondaryLabelColor).opacity(0.15))
            )
            .foregroundStyle(streamingEnabled ? Color.accentColor : Color(.secondaryLabelColor))
        }
        .buttonStyle(.plain)
        .help(streamingEnabled ? "Live streaming enabled — click to switch to batch" : "Batch mode — click to enable live streaming")
    }

    private var statusBadge: some View {
        Group {
            if isCurrent {
                Text("Default")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundStyle(.white)
            } else if isDownloaded {
                Text("Downloaded")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color(.quaternaryLabelColor)))
                    .foregroundStyle(Color(.labelColor))
            }
        }
    }

    private var metadataSection: some View {
        HStack(spacing: 12) {
            Label(model.language, systemImage: "globe")
            Label(model.size, systemImage: "internaldrive")
            HStack(spacing: 3) {
                Text("Speed")
                progressDotsWithNumber(value: model.speed * 10)
            }
            .fixedSize(horizontal: true, vertical: false)
            HStack(spacing: 3) {
                Text("Accuracy")
                progressDotsWithNumber(value: model.accuracy * 10)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .font(.system(size: 11))
        .foregroundStyle(Color(.secondaryLabelColor))
        .lineLimit(1)
    }

    private var descriptionSection: some View {
        Text(model.description)
            .font(.system(size: 11))
            .foregroundStyle(Color(.secondaryLabelColor))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    private var progressSection: some View {
        Group {
            if isDownloading {
                let progress = fluidAudioModelManager.downloadProgress[model.name] ?? 0.0
                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            }
        }
    }

    private var actionSection: some View {
        HStack(spacing: 8) {
            if isCurrent {
                Text("Default Model")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(.secondaryLabelColor))
            } else if isDownloaded {
                Button(action: {
                    Task {
                        transcriptionModelManager.setDefaultTranscriptionModel(model)
                    }
                }) {
                    Text("Set as Default")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button(action: {
                    Task {
                        await fluidAudioModelManager.downloadFluidAudioModel(model)
                    }
                }) {
                    HStack(spacing: 4) {
                        Text(isDownloading ? "Downloading..." : "Download")
                        Image(systemName: "arrow.down.circle")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.accentColor))
                }
                .buttonStyle(.plain)
                .disabled(isDownloading)
            }

            if isDownloaded {
                Menu("More options", systemImage: "ellipsis.circle") {
                    Button(action: {
                        fluidAudioModelManager.deleteFluidAudioModel(model)
                    }) {
                        Label("Delete Model", systemImage: "trash")
                    }

                    Button {
                        fluidAudioModelManager.showFluidAudioModelInFinder(model)
                    } label: {
                        Label("Show in Finder", systemImage: "folder")
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .labelStyle(.iconOnly)
                .frame(width: 20, height: 20)
            }
        }
    }
}
