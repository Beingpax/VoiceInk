import Foundation
import SwiftUI

struct DashboardProductivityPlotArea: View {
    @State private var hoveredPointID: Date?

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
                        horizontalSlotCount: horizontalSlotCount,
                        hoveredPointID: hoveredPointID
                    )

                    if !hasVisibleWords {
                        DashboardProductivityEmptyHint()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .padding(.bottom, 12)
                    }

                    hoverLayer(size: geometry.size, plotHeight: plotHeight)
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
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    ForEach(points.indices, id: \.self) { index in
                        let label = xAxisLabel(for: points[index], at: index)
                        if !label.isEmpty {
                            axisLabel(label)
                                .frame(width: 58, alignment: axisLabelAlignment(for: index))
                                .position(
                                    x: axisLabelPosition(
                                        for: index,
                                        width: geometry.size.width,
                                        labelWidth: 58
                                    ),
                                    y: 8
                                )
                        }
                    }
                }
            }
        }
    }

    private func hoverLayer(size: CGSize, plotHeight: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if let hoveredPoint, let hoveredIndex {
                DashboardProductivityHoverTooltip(
                    point: hoveredPoint,
                    previousPoint: previousPoint(before: hoveredIndex)
                )
                .position(
                    tooltipPosition(
                        for: plotPoint(for: hoveredIndex, width: size.width, height: plotHeight),
                        in: CGSize(width: size.width, height: plotHeight)
                    )
                )
                .allowsHitTesting(false)
            }

            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        updateHover(at: location, width: size.width)
                    case .ended:
                        hoveredPointID = nil
                    }
                }
        }
        .frame(width: size.width, height: plotHeight)
    }

    private var hoveredIndex: Int? {
        guard let hoveredPointID else { return nil }
        return visiblePoints.firstIndex { $0.id == hoveredPointID }
    }

    private var hoveredPoint: DashboardProductivityPoint? {
        guard let hoveredIndex else { return nil }
        return visiblePoints[hoveredIndex]
    }

    private func previousPoint(before index: Int) -> DashboardProductivityPoint? {
        guard index > 0 else { return nil }
        return visiblePoints[index - 1]
    }

    private func updateHover(at location: CGPoint, width: CGFloat) {
        guard !visiblePoints.isEmpty, width > 0, location.x >= 0, location.x <= width else {
            hoveredPointID = nil
            return
        }

        let nearestIndex = visiblePoints.indices.min { lhs, rhs in
            abs(xPosition(for: lhs, pointCount: visiblePoints.count, slotCount: horizontalSlotCount, width: width) - location.x)
                < abs(xPosition(for: rhs, pointCount: visiblePoints.count, slotCount: horizontalSlotCount, width: width) - location.x)
        }
        hoveredPointID = nearestIndex.map { visiblePoints[$0].id }
    }

    private func xPosition(for index: Int, pointCount: Int, slotCount: Int, width: CGFloat) -> CGFloat {
        let resolvedSlotCount = max(slotCount, pointCount)
        guard resolvedSlotCount > 1 else { return width / 2 }
        return width * CGFloat(index) / CGFloat(resolvedSlotCount - 1)
    }

    private func plotPoint(for index: Int, width: CGFloat, height: CGFloat) -> CGPoint {
        let maximum = max(yAxisUpperBound, 1)
        let progress = min(max(CGFloat(visiblePoints[index].words) / CGFloat(maximum), 0), 1)
        return CGPoint(
            x: xPosition(
                for: index,
                pointCount: visiblePoints.count,
                slotCount: horizontalSlotCount,
                width: width
            ),
            y: height - (height * progress)
        )
    }

    private func tooltipPosition(for point: CGPoint, in size: CGSize) -> CGPoint {
        let tooltipSize = CGSize(width: 208, height: 66)
        let gap: CGFloat = 12

        let canFitRight = point.x + gap + tooltipSize.width <= size.width
        let preferredX = canFitRight
            ? point.x + gap + tooltipSize.width / 2
            : point.x - gap - tooltipSize.width / 2
        let x = min(
            max(preferredX, tooltipSize.width / 2),
            max(tooltipSize.width / 2, size.width - tooltipSize.width / 2)
        )

        let canFitAbove = point.y - gap - tooltipSize.height >= 0
        let preferredY = canFitAbove
            ? point.y - gap - tooltipSize.height / 2
            : point.y + gap + tooltipSize.height / 2
        let y = min(
            max(preferredY, tooltipSize.height / 2),
            max(tooltipSize.height / 2, size.height - tooltipSize.height / 2)
        )

        return CGPoint(x: x, y: y)
    }

    private func axisLabelPosition(for index: Int, width: CGFloat, labelWidth: CGFloat) -> CGFloat {
        let pointX = xPosition(
            for: index,
            pointCount: points.count,
            slotCount: horizontalSlotCount,
            width: width
        )
        return min(max(pointX, labelWidth / 2), max(labelWidth / 2, width - labelWidth / 2))
    }

    private func axisLabelAlignment(for index: Int) -> Alignment {
        if index == 0 { return .leading }
        if index == points.count - 1 { return .trailing }
        return .center
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

private struct DashboardProductivityHoverTooltip: View {
    let point: DashboardProductivityPoint
    let previousPoint: DashboardProductivityPoint?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(point.accessibilityLabel)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Text.secondary)

            Text(wordsText(Formatters.formattedNumber(point.words)))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Text.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(comparisonText)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(comparisonColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 208, alignment: .leading)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
    }

    private var comparisonText: String {
        guard let previousPoint else {
            return String(localized: "Starting point")
        }

        let difference = point.words - previousPoint.words
        guard difference != 0 else {
            return wordsText(Formatters.formattedNumber(0)) + " (" + formattedPercentage(0) + ")"
        }

        let sign = difference > 0 ? "+" : "−"
        let formattedDifference = wordsText(sign + Formatters.formattedNumber(abs(difference)))

        guard previousPoint.words > 0 else {
            return formattedDifference + " (" + String(localized: "New") + ")"
        }

        let change = Double(abs(difference)) / Double(previousPoint.words)
        let formattedPercentage = formattedPercentage(change)
        return formattedDifference + " (" + sign + formattedPercentage + ")"
    }

    private func formattedPercentage(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0...1)))
    }

    private func wordsText(_ formattedNumber: String) -> String {
        String(format: String(localized: "%@ words"), formattedNumber)
    }

    private var comparisonColor: Color {
        guard let previousPoint else {
            return AppTheme.Text.muted
        }

        let difference = point.words - previousPoint.words
        if difference > 0 {
            return AppTheme.Status.positive.opacity(0.86)
        }
        if difference < 0 {
            return AppTheme.Status.error.opacity(0.86)
        }
        return AppTheme.Text.muted
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
