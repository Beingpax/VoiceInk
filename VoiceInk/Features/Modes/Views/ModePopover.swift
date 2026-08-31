import SwiftUI

struct ModePopover: View {
    @ObservedObject var modeManager = ModeManager.shared
    let selectedModeId: UUID?
    let onSelect: ((ModeConfig) -> Void)?

    init(selectedModeId: UUID? = nil, onSelect: ((ModeConfig) -> Void)? = nil) {
        self.selectedModeId = selectedModeId
        self.onSelect = onSelect
    }

    private var effectiveSelectedModeId: UUID? {
        modeManager.resolvedEnabledConfigurationId(preferredId: selectedModeId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Mode")
                .font(.headline)
                .foregroundColor(AppTheme.Text.primary)
                .padding(.horizontal)
                .padding(.top, 8)

            Divider()
                .background(AppTheme.Border.subtle)

            ScrollView {
                let enabledConfigs = modeManager.enabledConfigurations
                VStack(alignment: .leading, spacing: 4) {
                    if enabledConfigs.isEmpty {
                        VStack(alignment: .center, spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundColor(AppTheme.Text.secondary)
                                .font(.system(size: 16))
                            Text("No Modes Available")
                                .foregroundColor(AppTheme.Text.primary)
                                .font(.system(size: 13))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    } else {
                        ForEach(enabledConfigs) { config in
                            ModeRow(
                                config: config,
                                isSelected: effectiveSelectedModeId == config.id,
                                action: {
                                    if let onSelect {
                                        onSelect(config)
                                    } else {
                                        modeManager.setActiveConfiguration(config)
                                    }
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .frame(width: 180)
        .frame(maxHeight: 340)
        .padding(.vertical, 8)
        .background(AppTheme.Surface.window)
        .popoverAppAppearance()
    }
}

struct ModeRow: View {
    let config: ModeConfig
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ModeIconView(
                    icon: config.icon,
                    size: config.icon.kind == .emoji ? 14 : 12,
                    color: AppTheme.Text.primary
                )
                    .frame(width: 16)

                Text(config.name)
                    .foregroundColor(AppTheme.Text.primary)
                    .font(.system(size: 13))
                    .lineLimit(1)

                if isSelected {
                    Spacer()
                    Image(systemName: "checkmark")
                        .foregroundColor(AppTheme.Status.positive)
                        .font(.system(size: 10))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? AppTheme.Selection.fill : Color.clear)
        .cornerRadius(4)
    }
}
