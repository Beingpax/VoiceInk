import AppKit
import SwiftUI

// MARK: - Custom Model Card View
struct CustomModelCardView: View {
    let model: CustomCloudModel
    var deleteAction: () -> Void
    var editAction: (CustomCloudModel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main card content
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    headerSection
                    metadataSection
                    descriptionSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                actionSection
            }
            .padding(16)
        }
        .background(AppMaterialCardBackground())
    }

    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(.labelColor))

            Spacer()
        }
    }

    private var metadataSection: some View {
        HStack(spacing: 12) {
            Label(model.modelName, systemImage: "cube")
                .font(.system(size: 11))
                .foregroundColor(Color(.secondaryLabelColor))
                .lineLimit(1)

            // Language
            Label(model.language, systemImage: "globe")
                .font(.system(size: 11))
                .foregroundColor(Color(.secondaryLabelColor))
                .lineLimit(1)

            // OpenAI Compatible
            Label("OpenAI Compatible", systemImage: "checkmark.seal")
                .font(.system(size: 11))
                .foregroundColor(Color(.secondaryLabelColor))
                .lineLimit(1)
        }
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

    private var actionSection: some View {
        HStack(spacing: 8) {
            modelStatusPill("Configured", systemImage: "checkmark.circle")

            Menu {
                Button {
                    editAction(model)
                } label: {
                    Label("Edit Model", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    deleteAction()
                } label: {
                    Label("Delete Model", systemImage: "trash")
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
