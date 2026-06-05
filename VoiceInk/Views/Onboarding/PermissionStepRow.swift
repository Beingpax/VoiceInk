import SwiftUI

struct PermissionStepRow: View {
    let stepNumber: Int
    let descriptor: OnboardingPermissionDescriptor
    let status: OnboardingPermissionStatus
    let isActive: Bool
    let isLocked: Bool
    let showsRestartHint: Bool
    let actionTitle: String
    let onSelect: () -> Void
    let onAction: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                stepNumberView

                VStack(alignment: .leading, spacing: 4) {
                    Text(descriptor.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.Text.primary)

                    Text(descriptor.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.Text.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 10)

                if status.isGranted || isLocked {
                    statusBadge
                } else {
                    actionButton
                }
            }

            if isActive && !isLocked && showsRestartHint {
                restartHint
                    .padding(.leading, 44)
            }
        }
        .padding(14)
        .background(
            AppMaterialCardBackground(
                isSelected: isActive && !isLocked,
                cornerRadius: 10
            )
        )
        .opacity(isLocked ? 0.55 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture {
            guard !isLocked else { return }
            onSelect()
        }
    }

    private var stepNumberView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(status.isGranted ? AppTheme.Selection.fill : AppTheme.Surface.controlActive)

            if status.isGranted {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AppTheme.Text.primary)
            } else {
                Text("\(stepNumber)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isActive && !isLocked ? AppTheme.Text.primary : AppTheme.Text.muted)
            }
        }
        .frame(width: 30, height: 30)
    }

    private var actionButton: some View {
        Button(action: onAction) {
            Text(actionTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.Action.primaryForeground)
                .frame(minWidth: 94)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                        .fill(AppTheme.Action.primaryFill)
                )
        }
        .buttonStyle(.plain)
    }

    private var statusBadge: some View {
        Text(isLocked ? "Locked" : status.label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(isLocked ? AppTheme.Text.muted : statusTone)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isLocked ? AppTheme.Surface.subtle : statusTone.opacity(0.12))
            .clipShape(Capsule())
    }

    private var statusTone: Color {
        switch status {
        case .denied, .restricted:
            return AppTheme.Status.error
        default:
            return AppTheme.Text.secondary
        }
    }

    private var restartHint: some View {
        HStack(spacing: 8) {
            Text("Restart VoiceInk after enabling Screen Recording.")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.Text.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button("Quit") {
                onQuit()
            }
            .font(.system(size: 12, weight: .semibold))
            .buttonStyle(.plain)
            .foregroundColor(AppTheme.Action.secondaryForeground)
        }
    }
}
