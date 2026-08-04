import SwiftUI

struct VoiceInkButton: View {
    let title: LocalizedStringKey
    let action: () -> Void
    var isDisabled: Bool = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isDisabled ? AppTheme.Accent.disabled : AppTheme.Accent.primary)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

struct ModeEmptyStateView: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Modes")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Add customized modes for different contexts")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VoiceInkButton(
                title: "Add New Mode",
                action: action
            )
            .frame(maxWidth: 250)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ModeConfigurationsGrid: View {
    @ObservedObject var modeManager: ModeManager
    let onEditConfig: (ModeConfig) -> Void
    @EnvironmentObject var enhancementService: AIEnhancementService

    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach($modeManager.configurations) { $config in
                ConfigurationRow(
                    config: $config,
                    isEditing: false,
                    modeManager: modeManager,
                    onEditConfig: onEditConfig
                )
            }
        }
    }
}

struct DefaultModeIndicator: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 11, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)

            Text("Default")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.leading, 7)
        .padding(.trailing, 9)
        .frame(height: 24)
        .background {
            Capsule()
                .fill(AppTheme.Surface.card)
        }
        .overlay {
            Capsule()
                .strokeBorder(AppTheme.Border.control, lineWidth: 0.5)
        }
        .contentShape(Capsule())
        .help("Default mode is used when no app or website matches")
    }
}
