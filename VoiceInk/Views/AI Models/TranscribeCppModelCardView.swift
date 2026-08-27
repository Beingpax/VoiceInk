import SwiftUI

struct TranscribeCppModelCardView: View {
    let model: TranscribeCppModel
    @ObservedObject private var modelManager = TranscribeCppModelManager.shared

    private var isDownloaded: Bool { modelManager.isModelDownloaded(model) }
    private var isDownloading: Bool { modelManager.isModelDownloading(model) }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(.labelColor))

                    Spacer()
                }

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
                .foregroundColor(Color(.secondaryLabelColor))
                .lineLimit(1)

                Text(model.description)
                    .font(.system(size: 11))
                    .foregroundColor(Color(.secondaryLabelColor))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)

                progressSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actionSection
        }
        .padding(16)
        .background(AppMaterialCardBackground())
    }

    @ViewBuilder
    private var progressSection: some View {
        if let status = modelManager.downloadStatus(for: model) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(status.message)
                        .lineLimit(1)

                    if status.isIndeterminate {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.65)
                    }

                    Spacer()

                    Text(status.fractionCompleted, format: .percent.precision(.fractionLength(0)))
                        .fontDesign(.monospaced)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(.secondaryLabelColor))

                ProgressView(value: status.fractionCompleted)
                    .progressViewStyle(.linear)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .animation(.smooth, value: status.fractionCompleted)
        }
    }

    private var actionSection: some View {
        HStack(spacing: 8) {
            if isDownloaded && !isDownloading {
                modelStatusPill("Downloaded", systemImage: "checkmark.circle")

                Menu {
                    Button(role: .destructive) {
                        modelManager.deleteModel(model)
                    } label: {
                        Label("Delete Model", systemImage: "trash")
                    }

                    Button {
                        modelManager.showModelInFinder(model)
                    } label: {
                        Label("Show in Finder", systemImage: "folder")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 20, height: 20)
            } else {
                Button {
                    Task { await modelManager.downloadModel(model) }
                } label: {
                    HStack(spacing: 4) {
                        Text(LocalizedStringKey(isDownloading ? "Downloading..." : "Download"))
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
        }
    }
}
