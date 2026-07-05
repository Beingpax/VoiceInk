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
                .frame(height: 188)
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

private struct DashboardProductivityChart: View {
    let period: DashboardInsightPeriod
    let points: [DashboardProductivityPoint]

    private var axisMaximum: Int {
        Formatters.roundedChartMaximum(for: points.map(\.words).max() ?? 0)
    }

    private var axisLabels: [Int] {
        guard axisMaximum > 0 else { return [] }

        return [
            axisMaximum,
            axisMaximum * 3 / 4,
            axisMaximum / 2,
            axisMaximum / 4
        ]
        .filter { $0 > 0 }
        .reduce(into: []) { labels, value in
            if !labels.contains(value) {
                labels.append(value)
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DashboardProductivityScale(labels: axisLabels)
                .accessibilityHidden(true)

            DashboardProductivityPlot(
                period: period,
                points: points,
                axisMaximum: axisMaximum
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

private struct DashboardProductivityScale: View {
    let labels: [Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(labels, id: \.self) { label in
                    Text(Formatters.formattedAxisValue(label))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.Text.secondary)
                        .lineLimit(1)
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)

            Text("Words")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.Text.secondary.opacity(0.82))
                .lineLimit(1)
                .frame(height: 30, alignment: .topLeading)
        }
        .frame(width: 42, alignment: .leading)
    }
}

private struct DashboardProductivityPlot: View {
    let period: DashboardInsightPeriod
    let points: [DashboardProductivityPoint]
    let axisMaximum: Int

    private static let todayAxisHourOffsets = [0, 6, 12, 18, 24]

    private var hourFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = DashboardPeriodWindows.dashboardCalendar()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("j")
        return formatter
    }

    var body: some View {
        GeometryReader { geometry in
            let labelHeight: CGFloat = 30
            let plotHeight = max(0, geometry.size.height - labelHeight)

            ZStack(alignment: .topLeading) {
                DashboardProductivityGrid()
                    .frame(height: plotHeight)

                VStack(spacing: 0) {
                    HStack(alignment: .bottom, spacing: points.count > 14 ? 3 : 14) {
                        ForEach(points.indices, id: \.self) { index in
                            DashboardProductivityBar(
                                point: points[index],
                                axisMaximum: axisMaximum,
                                plotHeight: plotHeight
                            )
                        }
                    }
                    .frame(height: plotHeight, alignment: .bottom)

                    xAxisLabels
                        .accessibilityHidden(true)
                        .frame(height: labelHeight, alignment: .top)
                }
            }
        }
    }

    @ViewBuilder
    private var xAxisLabels: some View {
        if period == .today {
            HStack {
                ForEach(todayAxisLabels.indices, id: \.self) { index in
                    axisLabel(todayAxisLabels[index])

                    if index < todayAxisLabels.count - 1 {
                        Spacer(minLength: 0)
                    }
                }
            }
        } else {
            HStack(alignment: .top, spacing: points.count > 14 ? 3 : 14) {
                ForEach(points.indices, id: \.self) { index in
                    axisLabel(xAxisLabel(for: points[index], at: index))
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func axisLabel(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppTheme.Text.secondary)
            .lineLimit(1)
    }

    private var todayAxisLabels: [String] {
        guard let firstDate = points.first?.date else {
            return []
        }

        let calendar = DashboardPeriodWindows.dashboardCalendar()
        let formatter = hourFormatter

        return Self.todayAxisHourOffsets.compactMap { offset in
            calendar.date(byAdding: .hour, value: offset, to: firstDate).map {
                formatter.string(from: $0)
            }
        }
    }

    private func xAxisLabel(for point: DashboardProductivityPoint, at index: Int) -> String {
        switch period {
        case .today:
            return ""
        case .allTime:
            return monthlyAxisLabel(for: point, at: index)
        case .lastSevenDays, .lastThirtyDays, .thisYear:
            return defaultAxisLabel(for: point, at: index)
        }
    }

    private func defaultAxisLabel(for point: DashboardProductivityPoint, at index: Int) -> String {
        guard points.count > 14 else {
            return point.label
        }

        if index == 0 || index == points.count - 1 || (index + 1).isMultiple(of: 7) {
            return point.label
        }

        return ""
    }

    private func monthlyAxisLabel(for point: DashboardProductivityPoint, at index: Int) -> String {
        guard points.count > 12 else {
            return point.label
        }

        let labelStride: Int
        if points.count <= 24 {
            labelStride = 2
        } else if points.count <= 36 {
            labelStride = 3
        } else {
            labelStride = 6
        }

        if index == 0 || index == points.count - 1 || index.isMultiple(of: labelStride) {
            return point.label
        }

        return ""
    }
}

private struct DashboardProductivityGrid: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { index in
                Rectangle()
                    .fill(AppTheme.Border.subtle.opacity(index == 4 ? 0.9 : 0.45))
                    .frame(height: 1)

                if index < 4 {
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private struct DashboardProductivityBar: View {
    let point: DashboardProductivityPoint
    let axisMaximum: Int
    let plotHeight: CGFloat

    private var barHeight: CGFloat {
        guard axisMaximum > 0, point.words > 0 else { return 0 }
        return max(4, plotHeight * CGFloat(point.words) / CGFloat(axisMaximum))
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        AppTheme.Accent.strong,
                        AppTheme.Accent.primary.opacity(0.46)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(maxWidth: 22)
            .frame(height: barHeight)
            .frame(maxWidth: .infinity, alignment: .bottom)
            .shadow(color: AppTheme.Accent.primary.opacity(point.words > 0 ? 0.12 : 0), radius: 5, y: 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(point.accessibilityLabel)
            .accessibilityValue(wordsAccessibilityValue)
    }

    private var wordsAccessibilityValue: String {
        String(
            format: String(localized: "%@ words"),
            Formatters.formattedNumber(point.words)
        )
    }
}
