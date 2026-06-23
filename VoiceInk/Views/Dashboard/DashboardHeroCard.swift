import SwiftUI

struct DashboardHeroCard: View {
    let isLocked: Bool
    let headlinePrefix: String
    let highlightedValue: String
    let headlineSuffix: String
    let subtext: String
    let actionTitle: LocalizedStringKey
    let actionIcon: String
    let canViewInsights: Bool
    let actionHelp: String
    let actionAccessibilityLabel: String
    let onViewInsights: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isLocked {
                lockedInsightsPrompt
            } else {
                heroCopy
            }

            HStack(spacing: 12) {
                Button(action: onViewInsights) {
                    DashboardMomentumActionLabel(
                        title: actionTitle,
                        icon: actionIcon,
                        isPrimary: canViewInsights,
                        isLocked: !canViewInsights
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canViewInsights)
                .help(actionHelp)
                .accessibilityLabel(Text(actionAccessibilityLabel))
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 160, alignment: .leading)
        .background(DashboardImpactBackground(isLocked: isLocked))
        .clipShape(RoundedRectangle(cornerRadius: DashboardLayout.cardCornerRadius, style: .continuous))
    }

    private var heroCopy: some View {
        VStack(alignment: .leading, spacing: 10) {
            headlineText
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: 720, alignment: .leading)

            Text(subtext)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DashboardMomentumBackground.subtext)
                .lineLimit(2)
                .minimumScaleFactor(0.86)
                .frame(maxWidth: 620, alignment: .leading)
        }
    }

    private var headlineText: Text {
        Text(headlinePrefix)
            .font(.system(size: 23, weight: .bold, design: .rounded))
            .foregroundColor(DashboardMomentumBackground.headline) +
        Text(highlightedValue)
            .font(.system(size: 30, weight: .black, design: .rounded))
            .foregroundColor(DashboardMomentumBackground.accent) +
        Text(headlineSuffix)
            .font(.system(size: 23, weight: .bold, design: .rounded))
            .foregroundColor(DashboardMomentumBackground.headline)
    }

    private var lockedInsightsPrompt: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.78))

                Image(systemName: "lock.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(DashboardMomentumBackground.accent)
            }
            .frame(width: 42, height: 42)

            Text("Continue using VoiceInk to unlock stats and insights.")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(DashboardMomentumBackground.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.74)
                .frame(maxWidth: 540, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DashboardMomentumActionLabel: View {
    private static let cornerRadius: CGFloat = 12

    let title: LocalizedStringKey
    let icon: String
    let isPrimary: Bool
    var isLocked = false

    var body: some View {
        HStack(spacing: 9) {
            Text(title)

            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 18)
        .frame(height: 40)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .shadow(color: shadowColor, radius: 5, y: 2)
    }

    private var foregroundColor: Color {
        if isPrimary {
            return Color.white
        }

        return isLocked ? DashboardMomentumBackground.subtext : AppTheme.Text.primary
    }

    private var backgroundColor: Color {
        if isPrimary {
            return DashboardMomentumBackground.accent
        }

        return isLocked ? Color.white.opacity(0.64) : Color.white.opacity(0.82)
    }

    private var borderColor: Color {
        if isPrimary {
            return Color.clear
        }

        return isLocked ? DashboardMomentumBackground.accent.opacity(0.22) : Color.black.opacity(0.08)
    }

    private var shadowColor: Color {
        isPrimary ? DashboardMomentumBackground.accent.opacity(0.18) : Color.black.opacity(0.06)
    }
}

private struct DashboardImpactBackground: View {
    var isLocked = false

    var body: some View {
        ZStack {
            Image("momentum-hero-bg")
                .resizable()
                .scaledToFill()
                .blur(radius: isLocked ? 2.5 : 0)
                .saturation(isLocked ? 0.78 : 1)

            if isLocked {
                Color.white.opacity(0.32)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DashboardLayout.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DashboardLayout.cardCornerRadius, style: .continuous)
                .stroke(AppTheme.Border.card, lineWidth: 1)
        )
    }
}

private struct DashboardMomentumBackground {
    static let accent = Color(red: 0.76, green: 0.31, blue: 0.08)
    static let headline = Color(red: 0.10, green: 0.08, blue: 0.06)
    static let subtext = Color(red: 0.40, green: 0.34, blue: 0.28)
}
