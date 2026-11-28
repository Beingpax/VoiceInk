import SwiftUI

struct PermissionStepRow: View {
    let stepNumber: Int
    let descriptor: OnboardingPermissionDescriptor
    let status: OnboardingPermissionStatus
    let isActive: Bool
    let isLocked: Bool
    let showsRestartHint: Bool
    var guidance: String? = nil
    var help: ControlPermission.SetupHelp? = nil
    let actionTitle: String
    let onSelect: () -> Void
    let onAction: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                stepNumberView

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(LocalizedStringKey(descriptor.title))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.Text.primary)

                        if let help {
                            PermissionHelpButton(help: help)
                        }
                    }

                    Text(LocalizedStringKey(descriptor.subtitle))
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

            if isActive && !isLocked && !status.isGranted, let guidance {
                Text(guidance)
                    .font(.system(size: 12))
                    .foregroundColor(status == .limited ? AppTheme.Status.error : AppTheme.Text.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 44)
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
            Text(LocalizedStringKey(actionTitle))
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
        Text(isLocked ? LocalizedStringKey("Locked") : LocalizedStringKey(status.label))
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(isLocked ? AppTheme.Text.muted : statusTone)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isLocked ? AppTheme.Surface.subtle : statusTone.opacity(0.12))
            .clipShape(Capsule())
    }

    private var statusTone: Color {
        switch status {
        case .denied, .restricted, .limited:
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

/// An info button that shows how to grant a permission in System Settings.
private struct PermissionHelpButton: View {
    let help: ControlPermission.SetupHelp
    @State private var isShowingHelp = false

    var body: some View {
        Button {
            isShowingHelp.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.Text.muted)
        }
        .buttonStyle(.plain)
        .help(help.title)
        .accessibilityLabel(help.title)
        .popover(isPresented: $isShowingHelp, arrowEdge: .bottom) {
            PermissionHelpContent(help: help)
        }
    }
}

private struct PermissionHelpContent: View {
    let help: ControlPermission.SetupHelp

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(help.title)
                .font(.system(size: 13, weight: .semibold))

            ForEach(Array(help.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: "\(index + 1).")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                    Text(step)
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let fix = help.chosenAppsFix {
                Text(fix)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.Status.error)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Text(help.note)
                .font(.system(size: 11))
                .foregroundColor(AppTheme.Text.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
    }
}
