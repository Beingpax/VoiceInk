import SwiftUI
import AppKit

struct SenseVoiceModelCardView: View {
    let model: SenseVoiceModel
    @ObservedObject var whisperState: WhisperState
    let isCurrent: Bool
    let isDownloaded: Bool
    let downloadProgress: Double
    let downloadAction: () -> Void
    let deleteAction: () -> Void
    let setDefaultAction: () -> Void
    let showInFinderAction: () -> Void

    private var isDownloading: Bool {
        downloadProgress > 0 && downloadProgress < 1
    }

    private var clampedProgress: Double {
        max(0, min(downloadProgress, 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            statsSection
            descriptionSection
            progressSection
            actionSection
        }
        .padding(16)
        .background(CardBackground(isSelected: isCurrent, useAccentGradientWhenSelected: isCurrent))
    }

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.displayName)
                    .font(.system(size: 14, weight: .semibold))
                Text(model.size)
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                if !model.badges.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(model.badges, id: \.self) { badge in
                            Text(badge)
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color(nsColor: NSColor.controlBackgroundColor)))
                        }
                    }
                }
            }
            Spacer()
            if isCurrent {
                Text("Default")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundColor(.white)
            } else if isDownloaded {
                Text("Downloaded")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color(nsColor: .quaternaryLabelColor)))
            }
        }
    }

    private var statsSection: some View {
        HStack(spacing: 12) {
            Label(model.size, systemImage: "internaldrive")
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .lineLimit(1)
            
            HStack(spacing: 3) {
                Text("Speed")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                progressDotsWithNumber(value: model.speed * 10)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            
            HStack(spacing: 3) {
                Text("Accuracy")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                progressDotsWithNumber(value: model.accuracy * 10)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
        .lineLimit(1)
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.description)
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .lineLimit(2)
            if let highlight = model.highlight {
                Text(highlight)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(nsColor: .systemOrange))
            }
        }
    }

    private var progressSection: some View {
        Group {
            if isDownloading {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: clampedProgress)
                    Text("Downloading assets… \(Int(clampedProgress * 100))%")
                        .font(.system(size: 11))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                }
            }
        }
    }

    private var actionSection: some View {
        HStack(spacing: 12) {
            if isDownloaded {
                Button(action: setDefaultAction) {
                    Text(isCurrent ? "In Use" : "Set Default")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isCurrent)

                Menu {
                    Button(action: showInFinderAction) {
                        Label("Show in Finder", systemImage: "folder")
                    }
                    Button(role: .destructive, action: deleteAction) {
                        Label("Delete Files", systemImage: "trash")
                    }
                } label: {
                    Label("Manage", systemImage: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            } else {
                Button(action: downloadAction) {
                    HStack(spacing: 4) {
                        if isDownloading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.6)
                        }
                        Text(isDownloading ? "Downloading…" : "Download")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isDownloading)
            }
        }
    }
}
