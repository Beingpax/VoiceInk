import SwiftUI

struct DashboardActivityCalendarCard: View {
    private static let daysPerWeek = 7
    private static let cellSize: CGFloat = 18
    private static let cellSpacing: CGFloat = 5
    private static let hoverCoordinateSpace = "dashboardActivityCalendar"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredPoint: DashboardProductivityPoint?
    @State private var hoverLocation: CGPoint?

    let points: [DashboardProductivityPoint]
    let selectedPoints: [DashboardProductivityPoint]
    let peakHoursSummary: DashboardPeakHoursSummary
    let isPeakHoursLocked: Bool

    private var bestDayWords: Int {
        selectedPoints.lazy.map(\.words).max() ?? 0
    }

    private var activeDayCount: Int {
        selectedPoints.lazy.filter { $0.words > 0 }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 10) {
                Text("Consistency, at a glance")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.Text.primary)

                Spacer()

                HStack(spacing: 9) {
                    Text("Less")
                    RoundedRectangle(cornerRadius: 3)
                        .fill(AppTheme.Insights.grid)
                        .frame(width: 14, height: 14)
                    legendSwatch(opacity: 0.25)
                    legendSwatch(opacity: 0.5)
                    legendSwatch(opacity: 0.85)
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
                                .transition(.opacity)
                        }
                    }
                    .allowsHitTesting(false)
                }
                .coordinateSpace(name: Self.hoverCoordinateSpace)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hoveredPoint?.id)

            Divider()

            HStack(alignment: .top, spacing: 30) {
                metric(label: "Active days", value: Formatters.formattedCompactNumber(activeDayCount))
                metric(label: "Best day", value: activeDayCount > 0 ? "\(Formatters.formattedCompactNumber(bestDayWords)) words" : "--")
                metric(label: "Best time", value: peakWindowText)
            }
        }
        .dashboardInsightCardStyle(alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    private var activityGrid: some View {
        GeometryReader { geometry in
            let gridWidth = max(Self.cellSize, geometry.size.width)
            let visibleWeekCount = max(
                1,
                Int((gridWidth + Self.cellSpacing) / (Self.cellSize + Self.cellSpacing))
            )
            let columnSpacing = visibleWeekCount > 1
                ? (gridWidth - CGFloat(visibleWeekCount) * Self.cellSize) / CGFloat(visibleWeekCount - 1)
                : Self.cellSpacing
            let cells = calendarCells(weekCount: visibleWeekCount)
            let maximumWords = max(cells.lazy.filter { !$0.isFuture }.map { $0.point.words }.max() ?? 0, 1)

            LazyHGrid(rows: calendarRows, spacing: columnSpacing) {
                ForEach(cells) { cell in
                    if cell.isFuture {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(AppTheme.Insights.grid.opacity(0.45))
                            .frame(width: Self.cellSize, height: Self.cellSize)
                            .accessibilityLabel("\(cell.point.accessibilityLabel), future date")
                    } else {
                        compactActivityCell(point: cell.point, maximumWords: maximumWords)
                    }
                }
            }
            .frame(width: gridWidth, alignment: .leading)
            .padding(.vertical, 2)
            .onChange(of: cells.first?.id) { _, _ in
                clearHover()
            }
            .onChange(of: geometry.size.width) { _, _ in
                clearHover()
            }
        }
        .frame(height: CGFloat(Self.daysPerWeek) * Self.cellSize + CGFloat(Self.daysPerWeek - 1) * Self.cellSpacing + 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(points.contains { $0.words > 0 }
            ? Text("Recent daily dictation activity")
            : Text("No activity recorded"))
        .help("Recent activity from your full history. Empty cells indicate days without recorded activity.")
    }

    private var calendarRows: [GridItem] {
        Array(repeating: GridItem(.fixed(Self.cellSize), spacing: Self.cellSpacing), count: Self.daysPerWeek)
    }

    private func calendarCells(weekCount: Int) -> [DashboardCalendarCell] {
        let calendar = DashboardPeriodWindows.dashboardCalendar()
        let today = calendar.startOfDay(for: Date())
        let currentWeekStart = startOfWeek(containing: today, calendar: calendar)
        let firstWeek = calendar.date(
            byAdding: .weekOfYear,
            value: -(weekCount - 1),
            to: currentWeekStart
        ) ?? currentWeekStart
        let dayCount = weekCount * Self.daysPerWeek
        let pointsByDay = points.reduce(into: [Date: DashboardProductivityPoint]()) { result, point in
            result[calendar.startOfDay(for: point.date)] = point
        }
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = calendar
        dateFormatter.locale = .current
        dateFormatter.dateStyle = .full

        return (0..<dayCount).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: firstWeek) else {
                return nil
            }
            let day = calendar.startOfDay(for: date)
            let dateLabel = dateFormatter.string(from: day)
            let point = pointsByDay[day] ?? DashboardProductivityPoint(
                date: day,
                label: dateLabel,
                accessibilityLabel: dateLabel,
                words: 0
            )
            return DashboardCalendarCell(point: point, isFuture: day > today)
        }
    }

    private func startOfWeek(containing date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: day) - calendar.firstWeekday + Self.daysPerWeek) % Self.daysPerWeek
        return calendar.date(byAdding: .day, value: -offset, to: day) ?? day
    }

    private func compactActivityCell(point: DashboardProductivityPoint, maximumWords: Int) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(activityColor(words: point.words, maximumWords: maximumWords))
            .frame(width: Self.cellSize, height: Self.cellSize)
            .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
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
                            clearHover()
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

    private func clearHover() {
        hoveredPoint = nil
        hoverLocation = nil
    }

    private func activityColor(words: Int, maximumWords: Int) -> Color {
        guard words > 0 else { return AppTheme.Insights.grid }
        let ratio = min(CGFloat(words) / CGFloat(maximumWords), 1)
        return AppTheme.Insights.activity.opacity(0.25 + (ratio * 0.60))
    }

    private func legendSwatch(opacity: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(AppTheme.Insights.activity.opacity(opacity))
            .frame(width: 14, height: 14)
    }

    private func metric(label: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.Text.secondary)

            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Text.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var peakWindowText: String {
        guard !isPeakHoursLocked else {
            return String(localized: "Locked")
        }
        guard peakHoursSummary.hasData else {
            return String(localized: "Not enough data")
        }

        return "\(formattedHour(peakHoursSummary.startHour))–\(formattedHour(peakHoursSummary.endHour))"
    }

    private func formattedHour(_ hour: Int) -> String {
        let calendar = DashboardPeriodWindows.dashboardCalendar()
        let normalized = ((hour % 24) + 24) % 24
        let date = calendar.date(bySettingHour: normalized, minute: 0, second: 0, of: Date()) ?? Date()
        return Formatters.localizedHourFormatter(calendar: calendar).string(from: date)
    }
}

private struct DashboardCalendarCell: Identifiable {
    var id: Date { point.date }
    let point: DashboardProductivityPoint
    let isFuture: Bool
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
            AppTheme.Insights.elevated,
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
