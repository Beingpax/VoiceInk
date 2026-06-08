import AppKit
import SwiftUI

struct OnboardingLicenseSetupCard: View {
    @ObservedObject var licenseViewModel: LicenseViewModel

    let onPurchase: () -> Void
    let onStartTrial: () -> Void
    let onActivate: () -> Void

    private var canActivateLicense: Bool {
        !licenseViewModel.licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !licenseViewModel.isValidating
    }

    var body: some View {
        VStack(spacing: 16) {
            activationPanel
            licenseActions
        }
        .frame(maxWidth: .infinity)
    }

    private var activationPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("License key", text: $licenseViewModel.licenseKey)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .textCase(.uppercase)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.Surface.control.opacity(0.86))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppTheme.Border.control.opacity(0.42), lineWidth: 1)
                    )
                    .onSubmit {
                        if canActivateLicense {
                            onActivate()
                        }
                    }
                    .frame(maxWidth: .infinity)

                OnboardingLicensePrimaryButton(
                    title: "Activate",
                    systemImage: "key.fill",
                    isLoading: licenseViewModel.isValidating,
                    isEnabled: canActivateLicense,
                    action: onActivate
                )
                .frame(width: 118)
            }

            if let message = licenseViewModel.validationMessage {
                OnboardingLicenseStatusMessage(
                    message: message,
                    isSuccess: licenseViewModel.validationSuccess
                )
            }
        }
    }

    private var licenseActions: some View {
        HStack(spacing: 12) {
            OnboardingLicenseActionRow(
                title: "Purchase License",
                subtitle: "Lifetime access.",
                systemImage: "cart.fill",
                isEnabled: true,
                action: onPurchase
            )

            OnboardingLicenseActionRow(
                title: "Start 7-day Trial",
                subtitle: "Use VoiceInk now.",
                systemImage: "calendar",
                isEnabled: true,
                action: onStartTrial
            )
        }
    }
}

struct OnboardingVerifiedLicenseCard: View {
    let licenseKey: String

    @State private var didCopyLicenseKey = false

    var body: some View {
        LicenseActiveSummaryCard(
            title: "VoiceInk Pro",
            subtitle: "License active on this Mac.",
            licenseKey: licenseKey,
            didCopyLicenseKey: didCopyLicenseKey,
            onCopyLicenseKey: copyLicenseKey
        )
    }

    private func copyLicenseKey() {
        let key = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(key, forType: .string)

        withAnimation(.snappy(duration: 0.22)) {
            didCopyLicenseKey = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            withAnimation(.snappy(duration: 0.22)) {
                didCopyLicenseKey = false
            }
        }
    }
}

private struct OnboardingLicenseActionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(iconBackground)

                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(iconForeground)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.Text.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.88)

                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.Text.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(AppTheme.Text.disabled)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(AppTheme.Surface.subtle)
                    )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .background(tileBackground)
            .opacity(isEnabled ? 1 : 0.58)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    @ViewBuilder
    private var tileBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(AppTheme.Surface.control.opacity(0.76))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppTheme.Border.subtle, lineWidth: 1)
            )
    }

    private var iconBackground: Color {
        AppTheme.Surface.controlActive.opacity(0.72)
    }

    private var iconForeground: Color {
        AppTheme.Text.muted
    }
}

private struct OnboardingLicensePrimaryButton: View {
    let title: String
    let systemImage: String
    let isLoading: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }

                Text(isLoading ? "Activating" : title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(isEnabled ? AppTheme.Text.primary : AppTheme.Text.disabled)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isEnabled ? AppTheme.Surface.controlActive.opacity(0.88) : AppTheme.Surface.control.opacity(0.64))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isEnabled ? AppTheme.Border.control.opacity(0.48) : AppTheme.Border.subtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

private struct OnboardingLicenseStatusMessage: View {
    let message: String
    let isSuccess: Bool

    var body: some View {
        Label {
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(isSuccess ? AppTheme.Status.positive : AppTheme.Status.error)
    }
}
