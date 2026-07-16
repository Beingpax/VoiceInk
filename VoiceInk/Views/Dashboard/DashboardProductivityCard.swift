import Foundation
import SwiftUI

struct DashboardProductivityCard: View {
    @Binding var period: DashboardInsightPeriod
    let points: [DashboardProductivityPoint]
    let updatedAtText: String
    let isRefreshingStats: Bool
    let onRefreshStats: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                Text(period.chartTitle)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Text.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    Text(statusText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.Text.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.18), value: isRefreshingStats)

                    DashboardStatsRefreshButton(
                        isRefreshing: isRefreshingStats,
                        action: onRefreshStats
                    )
                }
                .frame(maxWidth: 260, alignment: .trailing)
            }

            DashboardProductivityChart(period: period, points: points)
                .frame(height: 208)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DashboardInsightCardBackground(cornerRadius: 16))
    }

    private var statusText: String {
        isRefreshingStats ? String(localized: "Updating") : updatedAtText
    }
}
struct DashboardProductivitySummaryStrip: View {
    let summary: DashboardTimeSavedSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            metricCell(
                title: "Time saved",
                value: summary.hasData ? Formatters.formattedSavedTime(summary.timeSaved) : "--",
                systemName: "clock"
            )
            metricCell(
                title: "Words dictated",
                value: summary.hasData ? Formatters.formattedCompactNumber(summary.wordCount) : "--",
                systemName: "list.bullet.rectangle"
            )
            metricCell(
                title: "Sessions",
                value: summary.hasData ? Formatters.formattedCompactNumber(summary.sessionCount) : "--",
                systemName: "mic"
            )
        }
    }

    private func metricCell(title: LocalizedStringKey, value: String, systemName: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(AppTheme.Surface.controlActive.opacity(0.72))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(AppTheme.Border.subtle.opacity(0.80), lineWidth: 1)
                    )

                Image(systemName: systemName)
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(AppTheme.Text.secondary.opacity(0.86))
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppTheme.Text.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Text(value)
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Text.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.66)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minWidth: 132, maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .background(DashboardInsightCardBackground(cornerRadius: 16))
    }
}

private struct DashboardStatsRefreshButton: View {
    let isRefreshing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(AppTheme.Accent.primary)
                        .transition(.opacity)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.Text.primary.opacity(0.72))
                        .transition(.opacity)
                }
            }
            .frame(width: 34, height: 34)
            .background(AppCardBackground(cornerRadius: 17))
            .animation(.easeInOut(duration: 0.18), value: isRefreshing)
        }
        .buttonStyle(.plain)
        .disabled(isRefreshing)
        .help(refreshHelp)
        .accessibilityLabel(Text(refreshHelp))
    }

    private var refreshHelp: String {
        isRefreshing ? String(localized: "Refreshing stats") : String(localized: "Refresh stats")
    }
}

private enum DashboardProductivityChartData {
    static func visiblePoints(
        for period: DashboardInsightPeriod,
        points: [DashboardProductivityPoint],
        now: Date = Date()
    ) -> [DashboardProductivityPoint] {
        Array(points.prefix(visiblePointCount(for: period, points: points, now: now)))
    }

    static func visiblePointCount(
        for period: DashboardInsightPeriod,
        points: [DashboardProductivityPoint],
        now: Date = Date()
    ) -> Int {
        guard period == .today, let firstPoint = points.first else {
            return points.count
        }

        let calendar = DashboardPeriodWindows.dashboardCalendar()

        guard calendar.isDate(firstPoint.date, inSameDayAs: now) else {
            return points.count
        }

        return min(points.count, calendar.component(.hour, from: now) + 1)
    }

    static func yAxisUpperBound(for value: Int) -> Int {
        guard value > 0 else {
            return 0
        }

        let paddedValue = Double(value) * 1.06
        let magnitude = pow(10, max(0, floor(log10(paddedValue)) - 1))
        let step = max(1, Int(magnitude))

        return max(value, Int(ceil(paddedValue / Double(step))) * step)
    }
}

private struct DashboardProductivityChart: View {
    let period: DashboardInsightPeriod
    let points: [DashboardProductivityPoint]

    private var yAxisUpperBound: Int {
        DashboardProductivityChartData.yAxisUpperBound(for: visiblePoints.map(\.words).max() ?? 0)
    }

    private var hasWords: Bool {
        visiblePoints.contains { $0.words > 0 }
    }

    private var visiblePoints: [DashboardProductivityPoint] {
        DashboardProductivityChartData.visiblePoints(for: period, points: points)
    }

    private var horizontalSlotCount: Int {
        period == .today ? 24 : max(visiblePoints.count, 1)
    }

    private var yAxisLabels: [Int] {
        guard hasWords else {
            return [0]
        }

        return [
            yAxisUpperBound,
            yAxisUpperBound * 3 / 4,
            yAxisUpperBound / 2,
            yAxisUpperBound / 4,
            0,
        ]
        .reduce(into: []) { labels, value in
            if !labels.contains(value) {
                labels.append(value)
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DashboardProductivityYAxis(labels: yAxisLabels)
                .accessibilityHidden(true)

            DashboardProductivityPlotArea(
                period: period,
                points: points,
                visiblePoints: visiblePoints,
                yAxisUpperBound: yAxisUpperBound,
                horizontalSlotCount: horizontalSlotCount
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dictated words chart")
        .accessibilityValue(totalWordsAccessibilityValue)
    }

    private var totalWordsAccessibilityValue: String {
        String(
            format: String(localized: "%@ words"),
            Formatters.formattedNumber(points.reduce(0) { $0 + $1.words })
        )
    }
}

private struct DashboardProductivityYAxis: View {
    let labels: [Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if labels.count == 1, let label = labels.first {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 0)
                    yAxisLabel(label)
                }
                .frame(maxHeight: .infinity, alignment: .bottomLeading)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(labels, id: \.self) { label in
                        yAxisLabel(label)
                            .frame(maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .topLeading)
            }

            Text("Words")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.Text.secondary.opacity(0.82))
                .lineLimit(1)
                .frame(height: 30, alignment: .topLeading)
        }
        .frame(width: 42, alignment: .leading)
    }

    private func yAxisLabel(_ label: Int) -> some View {
        Text(Formatters.formattedAxisValue(label))
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(AppTheme.Text.secondary)
            .lineLimit(1)
    }
}
