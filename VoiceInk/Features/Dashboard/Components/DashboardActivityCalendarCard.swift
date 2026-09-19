import SwiftUI

struct DashboardActivityCalendarCard: View {
    private static let columnCount = 7
    private static let hoverCoordinateSpace = "dashboardActivityCalendar"

    @State private var hoveredPoint: DashboardProductivityPoint?
    @State private var hoverLocation: CGPoint?

    let points: [DashboardProductivityPoint]
    let summary: DashboardTimeSavedSummary
    let peakHoursSummary: DashboardPeakHoursSummary
    let isPeakHoursLocked: Bool

    private var visiblePoints: [DashboardProductivityPoint] {
        points
    }

    private var maximumWords: Int {
        max(visiblePoints.map(\.words).max() ?? 0, 1)
    }

    private var averageWordsPerSession: Int {
        summary.sessionCount > 0 ? summary.wordCount / summary.sessionCount : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline) {
                Text("Consistency, at a glance")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Text.primary)

                Spacer()

                HStack(spacing: 9) {
                    Text("Less")
                    legendSwatch(opacity: 0.12)
                    legendSwatch(opacity: 0.38)
                    legendSwatch(opacity: 0.76)
                    Text("More")
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.Text.secondary)
                .accessibilityHidden(true)
            }

            activityGrid
                .overlay {
                    GeometryReader { geometry in
                        if let hoveredPoint, let hoverLocation {
                            DashboardActivityCalendarTooltip(point: hoveredPoint)
                                .position(tooltipPosition(for: hoverLocation, in: geometry.size))
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }
                    }
                    .allowsHitTesting(false)
                }
                .coordinateSpace(name: Self.hoverCoordinateSpace)
                .animation(.easeOut(duration: 0.12), value: hoveredPoint?.id)

            Divider()

            HStack(alignment: .top, spacing: 30) {
                metric(label: "Sessions", value: summary.hasData ? Formatters.formattedCompactNumber(summary.sessionCount) : "--", emphasized: true)
                metric(label: "Average output", value: summary.hasData ? "\(Formatters.formattedCompactNumber(averageWordsPerSession)) words" : "--")
                metric(label: "Best time", value: peakWindowText)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(DashboardInsightCardBackground(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var activityGrid: some View {
        if visiblePoints.isEmpty {
            LazyVGrid(columns: gridColumns, spacing: 7) {
                ForEach(0..<21, id: \.self) { _ in
                    emptyActivityCell
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("No activity recorded for this period")
        } else if visiblePoints.count <= 35 {
            LazyVGrid(columns: gridColumns, spacing: 9) {
                ForEach(calendarCells) { cell in
                    if let point = cell.point {
                        activityCell(point: point)
                    } else {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .accessibilityHidden(true)
                    }
                }
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHGrid(rows: calendarRows, spacing: 5) {
                        ForEach(calendarCells) { cell in
                            Group {
                                if let point = cell.point {
                                    compactActivityCell(point: point)
                                } else {
                                    Color.clear
                                        .frame(width: 14, height: 14)
                                        .accessibilityHidden(true)
                                }
                            }
                            .id(cell.id)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.visible)
                .onAppear {
                    scrollToLatest(using: proxy)
                }
                .onChange(of: latestCalendarCellID) { _, _ in
                    scrollToLatest(using: proxy)
                }
            }
        }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 7), count: Self.columnCount)
    }

    private var calendarRows: [GridItem] {
        Array(repeating: GridItem(.fixed(14), spacing: 5), count: Self.columnCount)
    }

    private var calendarCells: [DashboardCalendarCell] {
        guard let firstPoint = visiblePoints.first else { return [] }
        let calendar = DashboardPeriodWindows.dashboardCalendar()
        let weekday = calendar.component(.weekday, from: firstPoint.date)
        let leadingEmptyCount = (weekday - calendar.firstWeekday + 7) % 7
        let emptyCells = (0..<leadingEmptyCount).map { DashboardCalendarCell(id: "empty-\($0)", point: nil) }
        let activityCells = visiblePoints.map { DashboardCalendarCell(id: "day-\($0.date.timeIntervalSinceReferenceDate)", point: $0) }
        return emptyCells + activityCells
    }

    private var latestCalendarCellID: String? {
        calendarCells.last?.id
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        guard let latestCalendarCellID else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(latestCalendarCellID, anchor: .trailing)
        }
    }

    private func activityCell(point: DashboardProductivityPoint) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(activityColor(words: point.words))
            .aspectRatio(1, contentMode: .fit)
            .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay { hoverTrackingLayer(for: point) }
            .accessibilityLabel("\(point.accessibilityLabel), \(point.words) words")
    }

    private var emptyActivityCell: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(activityColor(words: 0))
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
    }

    private func compactActivityCell(point: DashboardProductivityPoint) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(activityColor(words: point.words))
            .frame(width: 14, height: 14)
            .contentShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay { hoverTrackingLayer(for: point) }
            .accessibilityLabel("\(point.accessibilityLabel), \(point.words) words")
    }

    private func hoverTrackingLayer(for point: DashboardProductivityPoint) -> some View {
        GeometryReader { geometry in
            Color.clear
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let frame = geometry.frame(in: .named(Self.hoverCoordinateSpace))
                        hoveredPoint = point
                        hoverLocation = CGPoint(
                            x: frame.minX + location.x,
                            y: frame.minY + location.y
                        )
                    case .ended:
                        if hoveredPoint?.id == point.id {
                            hoveredPoint = nil
                            hoverLocation = nil
                        }
                    }
                }
        }
    }

    private func tooltipPosition(for cursor: CGPoint, in size: CGSize) -> CGPoint {
        let tooltipSize = CGSize(width: 170, height: 58)
        let gap: CGFloat = 12
        let canFitRight = cursor.x + gap + tooltipSize.width <= size.width
        let proposedX = canFitRight
            ? cursor.x + gap + (tooltipSize.width / 2)
            : cursor.x - gap - (tooltipSize.width / 2)
        let canFitBelow = cursor.y + gap + tooltipSize.height <= size.height
        let proposedY = canFitBelow
            ? cursor.y + gap + (tooltipSize.height / 2)
            : cursor.y - gap - (tooltipSize.height / 2)

        return CGPoint(
            x: min(max(proposedX, tooltipSize.width / 2), max(tooltipSize.width / 2, size.width - tooltipSize.width / 2)),
            y: min(max(proposedY, tooltipSize.height / 2), max(tooltipSize.height / 2, size.height - tooltipSize.height / 2))
        )
    }

    private func activityColor(words: Int) -> Color {
        guard words > 0 else { return AppTheme.Surface.subtle }
        let ratio = min(CGFloat(words) / CGFloat(maximumWords), 1)
        return AppTheme.Accent.primary.opacity(0.18 + (ratio * 0.62))
    }

    private func legendSwatch(opacity: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(AppTheme.Accent.primary.opacity(opacity))
            .frame(width: 14, height: 14)
    }

    private func metric(label: LocalizedStringKey, value: String, emphasized: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.Text.secondary)

            Text(value)
                .font(.system(size: emphasized ? 28 : 18, weight: .bold, design: .rounded))
                .foregroundStyle(emphasized ? AppTheme.Accent.strong : AppTheme.Text.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var peakWindowText: String {
        guard !isPeakHoursLocked, peakHoursSummary.hasData else {
            return "Not enough data"
        }

        return "\(formattedHour(peakHoursSummary.startHour))–\(formattedHour(peakHoursSummary.endHour))"
    }

    private func formattedHour(_ hour: Int) -> String {
        let normalized = ((hour % 24) + 24) % 24
        let displayHour = normalized % 12 == 0 ? 12 : normalized % 12
        return "\(displayHour) \(normalized < 12 ? "AM" : "PM")"
    }
}

private struct DashboardCalendarCell: Identifiable {
    let id: String
    let point: DashboardProductivityPoint?
}

private struct DashboardActivityCalendarTooltip: View {
    let point: DashboardProductivityPoint

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(point.accessibilityLabel)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Text.secondary)

            Text(wordsText)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Text.primary)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minWidth: 150, alignment: .leading)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
    }

    private var wordsText: String {
        String(
            format: String(localized: "%@ words"),
            Formatters.formattedNumber(point.words)
        )
    }
}
