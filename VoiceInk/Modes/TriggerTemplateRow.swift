import SwiftUI

struct TriggerTemplateRow: View {
    let template: TriggerTemplate
    let group: ModeTriggerGroup
    let isAdded: Bool
    let isLoadingApps: Bool
    let onAdd: (ModeTriggerGroup) -> Void

    private var isDisabled: Bool {
        isAdded || isLoadingApps || group.isEmpty
    }

    var body: some View {
        Button {
            guard !isDisabled else { return }
            onAdd(group)
        } label: {
            HStack(spacing: 10) {
                TriggerSymbol(systemName: template.systemImage)

                Text(template.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isAdded ? .secondary : .primary)
                    .lineLimit(1)

                Spacer()

                if isAdded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                } else if !isDisabled {
                    TriggerGroupPreviewStack(appConfigs: group.appConfigs, urlConfigs: group.urlConfigs, tileSize: 24)
                        .padding(.trailing, 4)

                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(NSColor.separatorColor), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .help(isAdded ? "\(template.name) already added" : group.summaryText)
    }
}

struct TriggerSymbol: View {
    let systemName: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor))
                .frame(width: 28, height: 28)

            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        }
    }
}
