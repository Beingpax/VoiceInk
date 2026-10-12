import SwiftUI

struct DashboardTimeSavedSummary: Equatable {
    let timeSaved: TimeInterval
    let wordCount: Int
    let sessionCount: Int

    var hasData: Bool {
        sessionCount > 0 || wordCount > 0
    }
}

struct DashboardEditorialSummaryCard: View {
    let summary: DashboardTimeSavedSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("You made room for")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Text.primary)

            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(summary.hasData ? Formatters.formattedSavedTime(summary.timeSaved) : "--")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .tracking(-1)
                    .foregroundStyle(AppTheme.Insights.productivity)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .layoutPriority(1)

                Text("of focused work")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Text.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Rectangle()
                .fill(AppTheme.Insights.productivity.opacity(0.14))
                .frame(height: 1)
                .accessibilityHidden(true)

            HStack(alignment: .top, spacing: 20) {
                fact(
                    value: summary.hasData ? Formatters.formattedCompactNumber(summary.wordCount) : "--",
                    caption: "words captured"
                )
                fact(
                    value: summary.hasData ? Formatters.formattedCompactNumber(summary.sessionCount) : "--",
                    caption: "dictation sessions"
                )
                fact(
                    value: averageSessionText,
                    caption: "words per average session"
                )
            }
        }
        .dashboardInsightCardStyle()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("VoiceInk impact summary")
    }

    private var averageSessionText: String {
        guard summary.sessionCount > 0 else { return "--" }
        let average = Double(summary.wordCount) / Double(summary.sessionCount)
        if average >= 1000 {
            return Formatters.formattedCompactNumber(Int(average.rounded()))
        }
        return average.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func fact(value: String, caption: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .tracking(-0.4)
                .foregroundStyle(AppTheme.Text.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(caption)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Text.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
