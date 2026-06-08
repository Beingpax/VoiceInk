import SwiftUI

struct LicenseManagementView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var licenseViewModel = LicenseViewModel()
    @State private var showingDeactivateConfirmation = false
    @State private var didCopyLicenseKey = false
    @State private var isShowingReportPanel = false

    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    private let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    private let licenseTitleFont = Font.system(size: 28, weight: .semibold, design: .rounded)
    private let neutralIconColor = AppTheme.Text.secondary

    private var reportPanelAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.32)
    }

    private var reportPanelTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if isLicensed {
                        activeContent
                    } else {
                        inactiveContent
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isShowingReportPanel {
                bottomReportDismissLayer
                    .zIndex(1)

                reportPanelSurface
                    .transition(reportPanelTransition)
                    .zIndex(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 600, minHeight: 500)
        .confirmationDialog(
            "Deactivate License?",
            isPresented: $showingDeactivateConfirmation
        ) {
            Button("Deactivate License", role: .destructive) {
                licenseViewModel.removeLicense()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the license from this Mac. You can activate it again later.")
        }
    }

    private var bottomReportDismissLayer: some View {
        Color.clear
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: dismissReportPanel)
    }

    private var reportPanelSurface: some View {
        ReportFeedbackBottomPanel(
            onClose: dismissReportPanel,
            onEmail: {
                EmailSupport.openSupportEmail()
                dismissReportPanel()
            },
            onDiscord: {
                openURL("https://discord.gg/xryDy57nYD")
                dismissReportPanel()
            }
        )
        .onExitCommand(perform: dismissReportPanel)
    }

    private func showReportPanel() {
        withAnimation(reportPanelAnimation) {
            isShowingReportPanel = true
        }
    }

    private func dismissReportPanel() {
        withAnimation(reportPanelAnimation) {
            isShowingReportPanel = false
        }
    }

    private var isLicensed: Bool {
        if case .licensed = licenseViewModel.licenseState {
            return true
        }

        return false
    }

    private var inactiveContent: some View {
        VStack(spacing: 14) {
            purchasePanel
            activationPanel
            resourceDock
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var activeContent: some View {
        VStack(spacing: 14) {
            activeLicenseCard
            activeResourceDock
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var purchasePanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 18) {
                LicenseProMark()

                VStack(alignment: .leading, spacing: 5) {
                    Text("VoiceInk Pro")
                        .font(licenseTitleFont)

                    Text(trialSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                BenefitPill(title: "Lifetime access", systemImage: "infinity", tint: neutralIconColor)
                BenefitPill(title: "Free updates", systemImage: "arrow.down.circle.fill", tint: neutralIconColor)
                BenefitPill(title: "Priority support", systemImage: "bubble.left.and.bubble.right.fill", tint: neutralIconColor)
            }

            LicenseActionButton(
                title: "Buy License",
                systemImage: "checkmark.seal.fill",
                iconColor: neutralIconColor,
                fillsWidth: true
            ) {
                licenseViewModel.openPurchaseLink()
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppMaterialCardBackground(cornerRadius: 14))
    }

    private var activationPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Have a license key?")
                .font(.headline)

            HStack(spacing: 10) {
                TextField("License key", text: $licenseViewModel.licenseKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .textCase(.uppercase)

                LicenseActionButton(
                    title: "Activate",
                    systemImage: "key.fill",
                    iconColor: neutralIconColor,
                    fixedWidth: 112,
                    isLoading: licenseViewModel.isValidating,
                    loadingTitle: "Activating"
                ) {
                    Task { await licenseViewModel.validateLicense() }
                }
                .disabled(licenseViewModel.isValidating)
            }

            if let message = licenseViewModel.validationMessage {
                ValidationMessage(
                    message: message,
                    isSuccess: licenseViewModel.validationSuccess
                )
            }
        }
        .padding(18)
        .background(AppMaterialCardBackground(cornerRadius: 14))
    }

    private var activeLicenseCard: some View {
        LicenseActiveSummaryCard(
            title: "VoiceInk Pro",
            subtitle: "Version \(appVersion) (\(appBuild))",
            licenseKey: licenseViewModel.licenseKey,
            didCopyLicenseKey: didCopyLicenseKey,
            onCopyLicenseKey: copyLicenseKey
        ) {
            HStack(spacing: 10) {
                ResourceButton(title: "Manage License", systemImage: "person.crop.circle.badge.checkmark", tint: neutralIconColor) {
                    openLicensePortal()
                }

                ResourceButton(
                    title: "Deactivate",
                    systemImage: "xmark.circle.fill",
                    tint: neutralIconColor
                ) {
                    showingDeactivateConfirmation = true
                }
            }
        }
    }

    private var resourceDock: some View {
        HStack(spacing: 10) {
            ResourceButton(title: "Lost Key?", systemImage: "key.fill", tint: neutralIconColor) {
                openLicensePortal()
            }

            ResourceButton(title: "Report or Feedback", systemImage: "exclamationmark.bubble.fill", tint: neutralIconColor, action: showReportPanel)

            ResourceButton(title: "Docs", systemImage: "book.fill", tint: neutralIconColor) {
                openURL("https://tryvoiceink.com/docs")
            }
        }
    }

    private var activeResourceDock: some View {
        HStack(spacing: 10) {
            ResourceButton(title: "Changelog", systemImage: "list.bullet.clipboard.fill", tint: neutralIconColor) {
                openURL("https://github.com/Beingpax/VoiceInk/releases")
            }

            ResourceButton(title: "Report or Feedback", systemImage: "exclamationmark.bubble.fill", tint: neutralIconColor, action: showReportPanel)

            ResourceButton(title: "Docs", systemImage: "book.fill", tint: neutralIconColor) {
                openURL("https://tryvoiceink.com/docs")
            }
        }
    }

    private var trialSummary: String {
        switch licenseViewModel.licenseState {
        case .unlicensed:
            return "License required"
        case .licensed:
            return "Licensed"
        case .trial(let daysRemaining):
            return "\(daysRemaining) day\(daysRemaining == 1 ? "" : "s") left in trial"
        case .trialExpired:
            return "Trial ended"
        }
    }

    private func copyLicenseKey() {
        let key = licenseViewModel.licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func openLicensePortal() {
        openURL("https://polar.sh/beingpax/portal/request")
    }

    private func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

struct LicenseActiveSummaryCard<Actions: View>: View {
    let title: String
    let subtitle: String
    let licenseKey: String
    let didCopyLicenseKey: Bool
    let onCopyLicenseKey: () -> Void
    let actions: () -> Actions
    let showsActions: Bool

    init(
        title: String,
        subtitle: String,
        licenseKey: String,
        didCopyLicenseKey: Bool,
        onCopyLicenseKey: @escaping () -> Void,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.title = title
        self.subtitle = subtitle
        self.licenseKey = licenseKey
        self.didCopyLicenseKey = didCopyLicenseKey
        self.onCopyLicenseKey = onCopyLicenseKey
        self.actions = actions
        self.showsActions = true
    }

    init(
        title: String,
        subtitle: String,
        licenseKey: String,
        didCopyLicenseKey: Bool,
        onCopyLicenseKey: @escaping () -> Void
    ) where Actions == EmptyView {
        self.title = title
        self.subtitle = subtitle
        self.licenseKey = licenseKey
        self.didCopyLicenseKey = didCopyLicenseKey
        self.onCopyLicenseKey = onCopyLicenseKey
        self.actions = { EmptyView() }
        self.showsActions = false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 18) {
                LicenseProMark()

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            Divider()

            licenseKeyControl

            if showsActions {
                Divider()

                actions()
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppMaterialCardBackground(cornerRadius: 14))
    }

    private var licenseKeyControl: some View {
        HStack(spacing: 10) {
            Text("License Key")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .frame(width: 82, alignment: .leading)

            Button(action: onCopyLicenseKey) {
                HStack(spacing: 10) {
                    Text(maskedLicenseKey)
                        .font(.system(size: 18, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 10)

                    if didCopyLicenseKey {
                        CopiedStatePill()
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 42)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(didCopyLicenseKey ? AppTheme.Surface.controlActive : AppTheme.Surface.control)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(
                            didCopyLicenseKey ? AppTheme.Border.control : AppTheme.Border.subtle,
                            lineWidth: 1
                        )
                }
                .scaleEffect(didCopyLicenseKey ? 0.998 : 1)
                .animation(.smooth(duration: 0.18), value: didCopyLicenseKey)
            }
            .buttonStyle(.plain)
            .help(didCopyLicenseKey ? "Copied" : "Copy License Key")
        }
    }

    private var maskedLicenseKey: String {
        let key = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !key.isEmpty else {
            return "•••• •••• •••• ••••"
        }

        return "•••• •••• •••• \(key.suffix(4))"
    }
}

struct LicenseProMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.Surface.control)
                .frame(width: 92, height: 62)
                .rotationEffect(.degrees(-9))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.Border.subtle, lineWidth: 1)
                        .rotationEffect(.degrees(-9))
                )

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.Surface.materialCard)
                .frame(width: 92, height: 62)
                .rotationEffect(.degrees(8))
                .overlay(
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PRO")
                            .font(.caption)
                            .fontWeight(.semibold)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppTheme.Border.control)
                            .frame(width: 48, height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppTheme.Border.subtle)
                            .frame(width: 34, height: 4)
                    }
                    .padding(10)
                    .rotationEffect(.degrees(8))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.Border.card, lineWidth: 1)
                        .rotationEffect(.degrees(8))
                )
        }
        .frame(width: 120, height: 86)
    }
}

private struct ReportFeedbackBottomPanel: View {
    let onClose: () -> Void
    let onEmail: () -> Void
    let onDiscord: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 20) {
                VStack(spacing: 18) {
                    Text("Thank you for using VoiceInk")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Have feedback, a bug report, or something that feels off? Send a note with system information by email, or join Discord for community discussion. Every report helps make VoiceInk more reliable and easier to use.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 540)
                }

                Text("REACH OUT")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .tracking(0.6)

                HStack(spacing: 10) {
                    ReportPanelButton(
                        title: "Email Support",
                        systemImage: "envelope.fill",
                        iconColor: AppTheme.Text.secondary,
                        action: onEmail
                    )

                    ReportPanelButton(
                        title: "Join Discord",
                        systemImage: "bubble.left.and.bubble.right.fill",
                        iconColor: AppTheme.Text.secondary,
                        action: onDiscord
                    )
                }
                .frame(maxWidth: 380)
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 26)
            .frame(maxWidth: .infinity)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close")
            .padding(.top, 10)
            .padding(.trailing, 16)
        }
        .frame(maxWidth: .infinity)
        .background(SidePanelBackground())
        .overlay(Rectangle().fill(AppTheme.Border.tint).frame(height: 1), alignment: .top)
        .ignoresSafeArea(.container, edges: .bottom)
    }
}

private struct ReportPanelButton: View {
    let title: String
    let systemImage: String
    let iconColor: Color
    let action: () -> Void

    var body: some View {
        LicenseActionButton(
            title: title,
            systemImage: systemImage,
            iconColor: iconColor,
            fillsWidth: true,
            action: action
        )
    }
}

private struct BenefitPill: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.84)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.Surface.control)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.Border.subtle, lineWidth: 1)
        }
    }
}

private struct CopiedStatePill: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))

            Text("Copied")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(AppTheme.Surface.subtle))
        .overlay {
            Capsule()
                .stroke(AppTheme.Border.subtle, lineWidth: 1)
        }
    }
}

private struct ResourceButton: View {
    let title: String
    let systemImage: String
    var tint: Color = AppTheme.Text.secondary
    var foreground: Color = .primary
    let action: () -> Void

    var body: some View {
        LicenseActionButton(
            title: title,
            systemImage: systemImage,
            iconColor: tint,
            textColor: foreground,
            fillsWidth: true,
            action: action
        )
    }
}

private struct LicenseActionButton: View {
    let title: String
    let systemImage: String
    let iconColor: Color
    var textColor: Color = .primary
    var fixedWidth: CGFloat?
    var fillsWidth = false
    var isLoading = false
    var loadingTitle = "Loading"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
                .frame(width: fixedWidth)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
        }
        .buttonStyle(LicenseActionButtonStyle())
    }

    @ViewBuilder
    private var label: some View {
        if isLoading {
            ActivatingLicenseLabel(title: loadingTitle)
        } else {
            LicenseActionLabel(
                title: title,
                systemImage: systemImage,
                iconColor: iconColor,
                textColor: textColor
            )
        }
    }
}

private struct LicenseActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(
                Capsule()
                    .fill(configuration.isPressed ? AppTheme.Surface.controlActive : AppTheme.Surface.subtle)
            )
            .overlay {
                Capsule()
                    .stroke(AppTheme.Border.subtle, lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.55)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

private struct LicenseActionLabel: View {
    let title: String
    let systemImage: String
    let iconColor: Color
    var textColor: Color = .primary

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(iconColor)

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(textColor)
        }
    }
}

private struct ActivatingLicenseLabel: View {
    var title = "Activating"

    var body: some View {
        HStack(spacing: 7) {
            ProgressView()
                .controlSize(.small)

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        }
    }
}

private struct ValidationMessage: View {
    let message: String
    let isSuccess: Bool

    var body: some View {
        Label {
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
        }
        .foregroundStyle(isSuccess ? AppTheme.Status.positive : AppTheme.Status.error)
    }
}
