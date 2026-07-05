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
    private let savedTint = AppTheme.Accent.strong

    let summary: DashboardTimeSavedSummary
    let period: DashboardInsightPeriod

    private var savedTimeText: String {
        Formatters.formattedSavedTime(summary.timeSaved)
    }

    private var workdaySavingsText: String {
        guard summary.hasData, summary.timeSaved > 0 else {
            return String(localized: "Start dictating to build saved time.")
        }

        let fullWorkdays = Int((summary.timeSaved / TimeInterval(8 * 60 * 60)).rounded(.down))

        guard fullWorkdays >= 1 else {
            return String(
                format: String(localized: "That's %@ of workday savings."),
                Formatters.formattedCompactHoursAndMinutes(summary.timeSaved)
            )
        }

        let workdayText = String(localized: "\(fullWorkdays) workdays")
        let isOver = summary.timeSaved > (Double(fullWorkdays) * TimeInterval(8 * 60 * 60)) + 60
        let template = isOver ? String(localized: "That's over %@ saved.") : String(localized: "That's %@ saved.")

        return String(format: template, workdayText)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            DashboardInsightCardBackground(cornerRadius: 16)

            content
                .frame(height: 196 - (20 * 2), alignment: .topLeading)
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 196, maxHeight: 196, alignment: .topLeading)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("You saved")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Text.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.84)

            Text(summary.hasData ? savedTimeText : "--")
                .font(.system(size: 58, weight: .heavy, design: .rounded))
                .foregroundStyle(savedTint)
                .lineLimit(1)
                .minimumScaleFactor(0.46)

            Text(period.timeSavedContext)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Text.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 12)

            Text(workdaySavingsText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.Text.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
