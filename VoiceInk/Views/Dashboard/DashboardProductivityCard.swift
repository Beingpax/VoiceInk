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

private struct DashboardProductivityPlotArea: View {
    let period: DashboardInsightPeriod
    let points: [DashboardProductivityPoint]
    let visiblePoints: [DashboardProductivityPoint]
    let yAxisUpperBound: Int
    let horizontalSlotCount: Int

    private var hasVisibleWords: Bool {
        visiblePoints.contains { $0.words > 0 }
    }

    var body: some View {
        GeometryReader { geometry in
            let labelHeight: CGFloat = 30
            let plotHeight = max(0, geometry.size.height - labelHeight)

            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    DashboardProductivityGrid()

                    DashboardProductivityTrendLayer(
                        points: visiblePoints,
                        guideIndices: guideIndices,
                        yAxisUpperBound: yAxisUpperBound,
                        horizontalSlotCount: horizontalSlotCount
                    )

                    if !hasVisibleWords {
                        DashboardProductivityEmptyHint()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .padding(.bottom, 12)
                    }
                }
                .frame(height: plotHeight)

                xAxisLabels
                    .accessibilityHidden(true)
                    .frame(height: labelHeight, alignment: .top)
            }
        }
        .accessibilityChildren {
            ForEach(visiblePoints) { point in
                Text(point.accessibilityLabel)
                    .accessibilityValue(wordsAccessibilityValue(for: point.words))
            }
        }
    }

    @ViewBuilder
    private var xAxisLabels: some View {
        if period == .today {
            DashboardProductivityTodayAxisLabels(points: points)
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
        DashboardProductivityXAxisLabel(label: label)
    }

    private var guideIndices: [Int] {
        guard !visiblePoints.isEmpty else {
            return []
        }

        var indices = Set<Int>()

        if period == .today {
            for index in [0, 6, 12, 18, 23] where index < visiblePoints.count {
                indices.insert(index)
            }
        } else {
            for index in visiblePoints.indices where !xAxisLabel(for: points[index], at: index).isEmpty {
                indices.insert(index)
            }
        }

        indices.insert(visiblePoints.count - 1)
        return indices.sorted()
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

    private func wordsAccessibilityValue(for wordCount: Int) -> String {
        String(
            format: String(localized: "%@ words"),
            Formatters.formattedNumber(wordCount)
        )
    }
}

private struct DashboardProductivityEmptyHint: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.Text.secondary.opacity(0.78))

            Text("No dictated words in this period yet")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.Text.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.Border.subtle.opacity(0.58), lineWidth: 1)
                )
        )
        .accessibilityHidden(true)
    }
}

private struct DashboardProductivityXAxisLabel: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppTheme.Text.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }
}

private struct DashboardProductivityTodayAxisLabels: View {
    private struct AxisLabel: Identifiable {
        let offset: Int
        let text: String

        var id: Int { offset }
    }

    private static let hourOffsets = [0, 6, 12, 18, 23]
    private static let lastHourOffset = 23
    private static let labelWidth: CGFloat = 58

    let points: [DashboardProductivityPoint]

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(labels) { label in
                    let x = geometry.size.width * CGFloat(label.offset) / CGFloat(Self.lastHourOffset)
                    let clampedX = min(
                        max(x, Self.labelWidth / 2),
                        max(Self.labelWidth / 2, geometry.size.width - Self.labelWidth / 2)
                    )

                    DashboardProductivityXAxisLabel(label: label.text)
                        .frame(width: Self.labelWidth, alignment: alignment(for: label.offset))
                        .position(x: clampedX, y: 8)
                }
            }
        }
    }

    private var labels: [AxisLabel] {
        guard let firstDate = points.first?.date else {
            return []
        }

        let calendar = DashboardPeriodWindows.dashboardCalendar()
        let formatter = Formatters.localizedHourFormatter(calendar: calendar)

        return Self.hourOffsets.compactMap { offset in
            guard let date = calendar.date(byAdding: .hour, value: offset, to: firstDate) else {
                return nil
            }

            return AxisLabel(offset: offset, text: formatter.string(from: date))
        }
    }

    private func alignment(for offset: Int) -> Alignment {
        if offset == 0 {
            return .leading
        }

        if offset == Self.lastHourOffset {
            return .trailing
        }

        return .center
    }
}

private struct DashboardProductivityTrendLayer: View {
    let points: [DashboardProductivityPoint]
    let guideIndices: [Int]
    let yAxisUpperBound: Int
    let horizontalSlotCount: Int

    private let lineTint = AppTheme.Accent.strong

    private var hasVisibleData: Bool {
        points.contains { $0.words > 0 }
    }

    var body: some View {
        GeometryReader { geometry in
            let renderedPoints = Self.renderedPoints(
                for: points,
                yAxisUpperBound: yAxisUpperBound,
                horizontalSlotCount: horizontalSlotCount,
                size: geometry.size
            )
            let guideAnchors = Self.guideAnchors(for: guideIndices, in: renderedPoints)

            ZStack(alignment: .topLeading) {
                if renderedPoints.count > 0 {
                    if hasVisibleData {
                        DashboardProductivityAreaFillShape(points: renderedPoints)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        lineTint.opacity(0.30),
                                        lineTint.opacity(0.10),
                                        lineTint.opacity(0.015),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                        DashboardProductivityTrendLineShape(points: renderedPoints)
                            .stroke(
                                lineTint,
                                style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
                            )
                            .shadow(color: lineTint.opacity(0.12), radius: 2, y: 1)

                        ForEach(guideAnchors.dropLast()) { guide in
                            DashboardProductivityXAxisGuide(
                                height: geometry.size.height,
                                tint: lineTint
                            )
                            .position(x: guide.point.x, y: geometry.size.height / 2)
                        }

                        if let latestPoint = renderedPoints.last {
                            DashboardProductivityCurrentValueMarker(tint: lineTint)
                                .position(x: latestPoint.x, y: latestPoint.y)
                        }
                    } else {
                        DashboardProductivityBaselineShape()
                            .stroke(
                                AppTheme.Text.secondary.opacity(0.22),
                                style: StrokeStyle(lineWidth: 2, lineCap: .round)
                            )
                    }
                }
            }
        }
    }

    private static func renderedPoints(
        for points: [DashboardProductivityPoint],
        yAxisUpperBound: Int,
        horizontalSlotCount: Int,
        size: CGSize
    ) -> [CGPoint] {
        guard !points.isEmpty, size.width > 0, size.height > 0 else {
            return []
        }

        let maximum = max(yAxisUpperBound, 1)
        let slotCount = max(horizontalSlotCount, points.count)
        let denominator = max(slotCount - 1, 1)

        return points.enumerated().map { index, point in
            let x =
                slotCount == 1
                ? size.width / 2
                : size.width * CGFloat(index) / CGFloat(denominator)
            let progress = min(max(CGFloat(point.words) / CGFloat(maximum), 0), 1)
            let y = size.height - (size.height * progress)

            return CGPoint(x: x, y: y)
        }
    }

    private static func guideAnchors(for indices: [Int], in renderedPoints: [CGPoint])
        -> [DashboardProductivityGuideAnchor]
    {
        indices.compactMap { index in
            guard renderedPoints.indices.contains(index) else {
                return nil
            }

            return DashboardProductivityGuideAnchor(index: index, point: renderedPoints[index])
        }
    }
}

private struct DashboardProductivityGuideAnchor: Identifiable {
    let index: Int
    let point: CGPoint

    var id: Int { index }
}

private struct DashboardProductivityGrid: View {
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { index in
                    Rectangle()
                        .fill(AppTheme.Border.subtle.opacity(index == 4 ? 0.90 : 0.42))
                        .frame(height: 1)

                    if index < 4 {
                        Spacer(minLength: 0)
                    }
                }
            }

            HStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { index in
                    Rectangle()
                        .fill(AppTheme.Border.subtle.opacity(index == 0 ? 0.40 : 0.30))
                        .frame(width: 1)

                    if index < 4 {
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}

private struct DashboardProductivityAreaFillShape: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        guard let first = points.first else {
            return Path()
        }

        if points.count == 1 {
            let halfWidth = min(max(rect.width * 0.055, 10), 20)
            let left = max(rect.minX, first.x - halfWidth)
            let right = min(rect.maxX, first.x + halfWidth)

            var path = Path()
            path.move(to: CGPoint(x: left, y: rect.maxY))
            path.addCurve(
                to: first,
                control1: CGPoint(x: left, y: first.y),
                control2: CGPoint(x: first.x - halfWidth * 0.48, y: first.y)
            )
            path.addCurve(
                to: CGPoint(x: right, y: rect.maxY),
                control1: CGPoint(x: first.x + halfWidth * 0.48, y: first.y),
                control2: CGPoint(x: right, y: first.y)
            )
            path.closeSubpath()
            return path
        }

        var path = DashboardProductivityTrendLineShape(points: points).path(in: rect)
        if let last = points.last {
            path.addLine(to: CGPoint(x: last.x, y: rect.maxY))
        }
        path.addLine(to: CGPoint(x: first.x, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct DashboardProductivityTrendLineShape: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        guard let first = points.first else {
            return Path()
        }

        var path = Path()
        path.move(to: first)

        guard points.count > 1 else {
            return path
        }

        let tangents = monotoneTangents(for: points)

        for index in 0..<(points.count - 1) {
            let current = points[index]
            let next = points[index + 1]
            let distance = next.x - current.x
            let control1 = CGPoint(
                x: current.x + distance / 3,
                y: current.y + tangents[index] * distance / 3
            )
            let control2 = CGPoint(
                x: next.x - distance / 3,
                y: next.y - tangents[index + 1] * distance / 3
            )

            path.addCurve(
                to: next,
                control1: control1,
                control2: control2
            )
        }

        return path
    }

    private func monotoneTangents(for points: [CGPoint]) -> [CGFloat] {
        guard points.count > 1 else {
            return Array(repeating: 0, count: points.count)
        }

        let slopes = (0..<(points.count - 1)).map { index -> CGFloat in
            let current = points[index]
            let next = points[index + 1]
            let distance = next.x - current.x

            guard abs(distance) > .ulpOfOne else {
                return 0
            }

            return (next.y - current.y) / distance
        }

        var tangents = Array(repeating: CGFloat(0), count: points.count)
        tangents[0] = slopes[0]
        tangents[points.count - 1] = slopes[slopes.count - 1]

        guard points.count > 2 else {
            return tangents
        }

        for index in 1..<(points.count - 1) {
            let previousSlope = slopes[index - 1]
            let nextSlope = slopes[index]

            if previousSlope == 0 || nextSlope == 0 || previousSlope * nextSlope < 0 {
                tangents[index] = 0
            } else {
                tangents[index] = (previousSlope + nextSlope) / 2
            }
        }

        for index in slopes.indices {
            let slope = slopes[index]

            if slope == 0 {
                tangents[index] = 0
                tangents[index + 1] = 0
                continue
            }

            let firstRatio = tangents[index] / slope
            let secondRatio = tangents[index + 1] / slope
            let sum = firstRatio * firstRatio + secondRatio * secondRatio

            if sum > 9 {
                let scale = 3 / sqrt(sum)
                tangents[index] = scale * firstRatio * slope
                tangents[index + 1] = scale * secondRatio * slope
            }
        }

        return tangents
    }
}

private struct DashboardProductivityBaselineShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

private struct DashboardProductivityCurrentValueMarker: View {
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(width: 10, height: 10)

            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)

            Circle()
                .stroke(tint.opacity(0.20), lineWidth: 3)
                .frame(width: 14, height: 14)
        }
        .shadow(color: tint.opacity(0.12), radius: 2, y: 1)
        .accessibilityHidden(true)
    }
}

private struct DashboardProductivityXAxisGuide: View {
    let height: CGFloat
    let tint: Color

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        tint.opacity(0.00),
                        tint.opacity(0.10),
                        tint.opacity(0.04),
                        tint.opacity(0.00),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 1, height: height)
            .accessibilityHidden(true)
    }
}
