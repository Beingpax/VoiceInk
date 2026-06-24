import SwiftUI

struct DashboardProductivityCard: View {
    private static let cornerRadius: CGFloat = 16

    @Binding var period: DashboardProductivityPeriod
    let points: [DashboardProductivityPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                Text(period.chartTitle)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Text.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)

                Spacer(minLength: 12)
            }

            DashboardProductivityChart(period: period, points: points)
                .frame(height: 188)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppCardBackground(cornerRadius: Self.cornerRadius))
    }
}

private struct DashboardProductivityChart: View {
    let period: DashboardProductivityPeriod
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

            DashboardProductivityPlot(
                period: period,
                points: points,
                axisMaximum: axisMaximum
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Dictated words chart")
        .accessibilityValue("\(Formatters.formattedNumber(points.reduce(0) { $0 + $1.words })) words")
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
    let period: DashboardProductivityPeriod
    let points: [DashboardProductivityPoint]
    let axisMaximum: Int

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

                    HStack(alignment: .top, spacing: points.count > 14 ? 3 : 14) {
                        ForEach(points.indices, id: \.self) { index in
                            Text(xAxisLabel(for: points[index], at: index))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppTheme.Text.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: labelHeight, alignment: .top)
                }
            }
        }
    }

    private func xAxisLabel(for point: DashboardProductivityPoint, at index: Int) -> String {
        switch period {
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
            .accessibilityLabel(point.accessibilityLabel)
            .accessibilityValue("\(Formatters.formattedNumber(point.words)) words")
    }
}
