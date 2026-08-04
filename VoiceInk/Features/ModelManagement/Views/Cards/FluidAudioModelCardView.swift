import AppKit
import SwiftUI

struct FluidAudioModelCardView: View {
    let model: FluidAudioModel
    @ObservedObject var fluidAudioModelManager: FluidAudioModelManager

    init(model: FluidAudioModel, fluidAudioModelManager: FluidAudioModelManager) {
        self.model = model
        _fluidAudioModelManager = ObservedObject(wrappedValue: fluidAudioModelManager)
    }

    var isDownloaded: Bool {
        fluidAudioModelManager.isFluidAudioModelDownloaded(model)
    }

    var isDownloading: Bool {
        fluidAudioModelManager.isFluidAudioModelDownloading(model)
    }

    private var showsExperimentalBadge: Bool {
        FluidAudioModelManager.isParakeetUnifiedModel(named: model.name)
            || FluidAudioModelManager.isNemotronModel(named: model.name)
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
        .background(AppMaterialCardBackground())
    }

    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(.labelColor))

            if showsExperimentalBadge {
                Text("Experimental")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color(red: 0.96, green: 0.79, blue: 0.63)))
            }

            Spacer()
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
        .foregroundColor(Color(.secondaryLabelColor))
        .lineLimit(1)
    }

    private var descriptionSection: some View {
        Text(model.description)
            .font(.system(size: 11))
            .foregroundColor(Color(.secondaryLabelColor))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    private var progressSection: some View {
        Group {
            if let status = fluidAudioModelManager.downloadStatus(for: model) {
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
                        .progressViewStyle(LinearProgressViewStyle())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
                .animation(.smooth, value: status.fractionCompleted)
            }
        }
    }

    private var actionSection: some View {
        HStack(spacing: 8) {
            if isDownloaded && !isDownloading {
                modelStatusPill("Downloaded", systemImage: "checkmark.circle")
            } else {
                Button(action: {
                    Task {
                        await fluidAudioModelManager.downloadFluidAudioModel(model)
                    }
                }) {
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

            if isDownloaded && !isDownloading {
                Menu {
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

                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 20, height: 20)
            }
        }
    }
}
