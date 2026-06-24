import SwiftUI

struct DashboardTimeSavedSummary: Equatable {
    let timeSaved: TimeInterval
    let wordCount: Int
    let sessionCount: Int

    var hasData: Bool {
        sessionCount > 0 || wordCount > 0
    }
}

struct DashboardTimeSavedCard: View {
    private static let cornerRadius: CGFloat = 16
    private static let cardHeight: CGFloat = 196
    private let savedTint = AppTheme.Accent.strong

    let summary: DashboardTimeSavedSummary

    private var savedTimeText: String {
        Formatters.formattedCompactHoursAndMinutes(summary.timeSaved)
    }

    private var wordText: String {
        Formatters.formattedCompactNumber(summary.wordCount)
    }

    private var sessionText: String {
        Formatters.formattedCompactNumber(summary.sessionCount)
    }

    private var accessibilitySummary: String {
        let sessionLabel = summary.sessionCount == 1 ? "session" : "sessions"
        return "Dictated \(wordText) words across \(sessionText) \(sessionLabel)."
    }

    private var accessibilityValue: String {
        guard summary.hasData else {
            return "No time saved yet."
        }

        return "\(savedTimeText) saved with VoiceInk. \(accessibilitySummary)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("You saved")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Text.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.84)

            VStack(spacing: 0) {
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(summary.hasData ? savedTimeText : "--")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(savedTint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.50)

                        Text("with VoiceInk")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Text.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.bottom, 14)

                Divider()
                    .opacity(0.5)

                HStack(spacing: 0) {
                    DashboardSavedLedgerMetric(
                        label: "Words dictated",
                        value: summary.hasData ? wordText : "--",
                        isTrailing: false
                    )

                    Spacer(minLength: 12)

                    Rectangle()
                        .fill(AppTheme.Border.subtle)
                        .frame(width: 1, height: 32)

                    Spacer(minLength: 12)

                    DashboardSavedLedgerMetric(
                        label: "Sessions",
                        value: summary.hasData ? sessionText : "--",
                        isTrailing: true
                    )
                }
                .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: Self.cardHeight, maxHeight: Self.cardHeight, alignment: .topLeading)
        .background(AppCardBackground(cornerRadius: Self.cornerRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Time saved")
        .accessibilityValue(accessibilityValue)
    }

}

private struct DashboardSavedLedgerMetric: View {
    let label: LocalizedStringKey
    let value: String
    let isTrailing: Bool

    var body: some View {
        VStack(alignment: isTrailing ? .trailing : .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Text.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.70)

            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppTheme.Text.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: isTrailing ? .trailing : .leading)
    }
}
