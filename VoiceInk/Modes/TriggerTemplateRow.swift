import SwiftUI

struct TriggerTemplateRow: View {
    let template: TriggerTemplate
    let group: ModeTriggerGroup
    let isAdded: Bool
    let isLoadingApps: Bool
    let onToggle: (ModeTriggerGroup) -> Void

    private var isDisabled: Bool {
        isLoadingApps || (!isAdded && group.isEmpty)
    }

    private var cardBackground: Color {
        isAdded ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : Color.clear
    }

    private var cardBorder: Color {
        isAdded ? Color(nsColor: .separatorColor) : AppTheme.Border.control
    }

    var body: some View {
        Button {
            guard !isDisabled else { return }
            onToggle(group)
        } label: {
            HStack(spacing: 10) {
                TriggerSymbol(systemName: template.systemImage)

                Text(template.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                if !group.isEmpty {
                    TriggerGroupPreviewStack(appConfigs: group.appConfigs, urlConfigs: group.urlConfigs, tileSize: 24)
                        .padding(.trailing, 4)
                }

                if isAdded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 22, height: 22)
                } else if !isDisabled {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(cardBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(cardBorder, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .help(isAdded ? "Remove \(template.name) triggers" : group.summaryText)
    }
}

struct TriggerSymbol: View {
    let systemName: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(AppTheme.Surface.control)
                .frame(width: 28, height: 28)

            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        }
    }
}
