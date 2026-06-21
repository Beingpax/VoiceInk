import SwiftUI
import AppKit

struct DashboardPromotionsSection: View {
    let licenseState: LicenseViewModel.LicenseState
    @State private var isAffiliatePromotionDismissed: Bool = UserDefaults.standard.affiliatePromotionDismissed

    private let affiliateCommission = 0.30

    private var affiliateCommissionText: String {
        affiliateCommission.formatted(.percent.precision(.fractionLength(0)))
    }

    private var affiliatePromotionBadge: String {
        String.localizedStringWithFormat(String(localized: "AFFILIATE %@"), affiliateCommissionText)
    }

    private var affiliatePromotionMessage: String {
        String.localizedStringWithFormat(
            String(localized: "Share VoiceInk with friends or your audience and receive %@ on every referral that upgrades."),
            affiliateCommissionText
        )
    }

    var body: some View {
        if case .licensed = licenseState, !isAffiliatePromotionDismissed {
            DashboardPromotionCard(
                badge: affiliatePromotionBadge,
                title: "Earn With The VoiceInk Affiliate Program",
                message: affiliatePromotionMessage,
                accentSymbol: "link.badge.plus",
                glowColor: Color(red: 0.08, green: 0.48, blue: 0.85),
                actionTitle: "Explore Affiliate",
                actionIcon: "arrow.up.right",
                action: openAffiliateProgram,
                onDismiss: dismissAffiliatePromotion
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            EmptyView()
        }
    }
    
    private func openAffiliateProgram() {
        if let url = URL(string: "https://tryvoiceink.com/affiliate") {
            NSWorkspace.shared.open(url)
        }
    }

    private func dismissAffiliatePromotion() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isAffiliatePromotionDismissed = true
        }
        UserDefaults.standard.affiliatePromotionDismissed = true
    }
}

private struct DashboardPromotionCard: View {
    let badge: String
    let title: LocalizedStringKey
    let message: String
    let accentSymbol: String
    let glowColor: Color
    let actionTitle: LocalizedStringKey
    let actionIcon: String
    let action: () -> Void
    var onDismiss: (() -> Void)? = nil

    private static let defaultGradient: LinearGradient = LinearGradient(
        colors: [
            Color(red: 0.08, green: 0.48, blue: 0.85),
            Color(red: 0.05, green: 0.18, blue: 0.42)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 14) {
                Text(badge)
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.2))
                    .clipShape(Capsule())
                    .foregroundColor(.white)

                Text(title)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: action) {
                    HStack(spacing: 6) {
                        Text(actionTitle)
                        Image(systemName: actionIcon)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(.white.opacity(0.22))
                    .clipShape(Capsule())
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)

            if let onDismiss = onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .padding(12)
                .help("Dismiss this promotion")
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Self.defaultGradient)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: glowColor.opacity(0.15), radius: 12, x: 0, y: 8)
    }
}
