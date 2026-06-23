import Foundation
import SwiftData

enum DashboardStatsLoader {
    static func load(from modelContainer: ModelContainer) async throws -> DashboardStatsSummary {
        let task = Task.detached(priority: .utility) {
            try Task.checkCancellation()

            let backgroundContext = ModelContext(modelContainer)
            let count = try backgroundContext.fetchCount(FetchDescriptor<SessionMetric>())

            try Task.checkCancellation()

            var words = 0
            var duration: TimeInterval = 0
            var recentSevenDayCount = 0
            var recentSevenDayWords = 0
            var recentSevenDayDuration: TimeInterval = 0
            var previousSevenDayCount = 0
            var previousSevenDayWords = 0
            var previousSevenDayDuration: TimeInterval = 0
            var lastThirtyDayCount = 0
            var lastThirtyDayWords = 0
            var lastThirtyDayDuration: TimeInterval = 0
            var thisYearCount = 0
            var thisYearWords = 0
            var thisYearDuration: TimeInterval = 0
            var lastSevenDayTranscriptionUsage: [String: DashboardModelUsageAccumulator] = [:]
            var lastSevenDayEnhancementUsage: [String: DashboardModelUsageAccumulator] = [:]
            var lastThirtyDayTranscriptionUsage: [String: DashboardModelUsageAccumulator] = [:]
            var lastThirtyDayEnhancementUsage: [String: DashboardModelUsageAccumulator] = [:]
            var thisYearTranscriptionUsage: [String: DashboardModelUsageAccumulator] = [:]
            var thisYearEnhancementUsage: [String: DashboardModelUsageAccumulator] = [:]
            var allTimeTranscriptionUsage: [String: DashboardModelUsageAccumulator] = [:]
            var allTimeEnhancementUsage: [String: DashboardModelUsageAccumulator] = [:]
            var lastSevenDayPeakHours: [Int: DashboardPeakHourAccumulator] = [:]
            var lastThirtyDayPeakHours: [Int: DashboardPeakHourAccumulator] = [:]
            var thisYearPeakHours: [Int: DashboardPeakHourAccumulator] = [:]
            var allTimePeakHours: [Int: DashboardPeakHourAccumulator] = [:]
            var allTimeMonthWords: [Date: Int] = [:]
            var firstMetricDate: Date?
            let windows = DashboardPeriodWindows()
            let now = windows.now
            let calendar = windows.calendar
            var lastSevenDayProductivity = Self.productivityPoints(dayCount: 7, now: now, calendar: calendar, labelStyle: .weekday)
            var lastThirtyDayProductivity = Self.productivityPoints(dayCount: 30, now: now, calendar: calendar, labelStyle: .dayOfMonth)
            var thisYearProductivity = Self.monthlyProductivityPoints(from: windows.thisYearStart, through: now, calendar: calendar)
            let sevenDayIndices = Dictionary(uniqueKeysWithValues: lastSevenDayProductivity.enumerated().map { index, point in
                (calendar.startOfDay(for: point.date), index)
            })
            let thirtyDayIndices = Dictionary(uniqueKeysWithValues: lastThirtyDayProductivity.enumerated().map { index, point in
                (calendar.startOfDay(for: point.date), index)
            })
            let thisYearMonthIndices = Dictionary(uniqueKeysWithValues: thisYearProductivity.enumerated().map { index, point in
                (startOfMonth(for: point.date, calendar: calendar), index)
            })
            let batchSize = 500
            var offset = 0

            while offset < count {
                try Task.checkCancellation()

                var descriptor = FetchDescriptor<SessionMetric>(
                    sortBy: [SortDescriptor(\SessionMetric.timestamp, order: .forward)]
                )
                descriptor.fetchLimit = batchSize
                descriptor.fetchOffset = offset

                let records = try backgroundContext.fetch(descriptor)
                if records.isEmpty {
                    break
                }

                if firstMetricDate == nil {
                    firstMetricDate = records.first?.timestamp
                }

                for metric in records {
                    words += metric.wordCount
                    duration += metric.audioDuration

                    if windows.recentSevenDayInterval.contains(metric.timestamp) {
                        recentSevenDayCount += 1
                        recentSevenDayWords += metric.wordCount
                        recentSevenDayDuration += metric.audioDuration
                    } else if windows.previousSevenDayInterval.contains(metric.timestamp) {
                        previousSevenDayCount += 1
                        previousSevenDayWords += metric.wordCount
                        previousSevenDayDuration += metric.audioDuration
                    }

                    if windows.recentThirtyDayInterval.contains(metric.timestamp) {
                        lastThirtyDayCount += 1
                        lastThirtyDayWords += metric.wordCount
                        lastThirtyDayDuration += metric.audioDuration
                    }

                    if windows.thisYearInterval.contains(metric.timestamp) {
                        thisYearCount += 1
                        thisYearWords += metric.wordCount
                        thisYearDuration += metric.audioDuration
                    }

                    let metricDay = calendar.startOfDay(for: metric.timestamp)
                    if let weekIndex = sevenDayIndices[metricDay] {
                        lastSevenDayProductivity[weekIndex].words += metric.wordCount
                    }
                    if let monthIndex = thirtyDayIndices[metricDay] {
                        lastThirtyDayProductivity[monthIndex].words += metric.wordCount
                    }
                    if windows.thisYearInterval.contains(metric.timestamp) {
                        let metricMonth = startOfMonth(for: metric.timestamp, calendar: calendar)
                        if let thisYearIndex = thisYearMonthIndices[metricMonth] {
                            thisYearProductivity[thisYearIndex].words += metric.wordCount
                        }
                    }
                    allTimeMonthWords[startOfMonth(for: metric.timestamp, calendar: calendar), default: 0] += metric.wordCount

                    let metricHour = calendar.component(.hour, from: metric.timestamp)

                    if windows.recentSevenDayInterval.contains(metric.timestamp) {
                        addModelUsage(
                            for: metric,
                            transcriptionUsage: &lastSevenDayTranscriptionUsage,
                            enhancementUsage: &lastSevenDayEnhancementUsage
                        )
                        addPeakHour(for: metric, hour: metricHour, to: &lastSevenDayPeakHours)
                    }
                    if windows.recentThirtyDayInterval.contains(metric.timestamp) {
                        addModelUsage(
                            for: metric,
                            transcriptionUsage: &lastThirtyDayTranscriptionUsage,
                            enhancementUsage: &lastThirtyDayEnhancementUsage
                        )
                        addPeakHour(for: metric, hour: metricHour, to: &lastThirtyDayPeakHours)
                    }
                    if windows.thisYearInterval.contains(metric.timestamp) {
                        addModelUsage(
                            for: metric,
                            transcriptionUsage: &thisYearTranscriptionUsage,
                            enhancementUsage: &thisYearEnhancementUsage
                        )
                        addPeakHour(for: metric, hour: metricHour, to: &thisYearPeakHours)
                    }
                    addModelUsage(
                        for: metric,
                        transcriptionUsage: &allTimeTranscriptionUsage,
                        enhancementUsage: &allTimeEnhancementUsage
                    )
                    addPeakHour(for: metric, hour: metricHour, to: &allTimePeakHours)
                }

                offset += records.count
            }

            try Task.checkCancellation()

            let allTimeProductivity: [DashboardProductivityPoint] = {
                guard let firstMetricDate else { return [] }
                return Self.monthlyProductivityPoints(
                    from: firstMetricDate,
                    through: now,
                    calendar: calendar,
                    wordsByMonth: allTimeMonthWords
                )
            }()

            return DashboardStatsSummary(
                totalCount: count,
                totalWords: words,
                totalDuration: duration,
                recentSevenDayCount: recentSevenDayCount,
                recentSevenDayWords: recentSevenDayWords,
                recentSevenDayDuration: recentSevenDayDuration,
                previousSevenDayCount: previousSevenDayCount,
                previousSevenDayWords: previousSevenDayWords,
                previousSevenDayDuration: previousSevenDayDuration,
                lastThirtyDayCount: lastThirtyDayCount,
                lastThirtyDayWords: lastThirtyDayWords,
                lastThirtyDayDuration: lastThirtyDayDuration,
                thisYearCount: thisYearCount,
                thisYearWords: thisYearWords,
                thisYearDuration: thisYearDuration,
                lastSevenDayProductivity: lastSevenDayProductivity,
                lastThirtyDayProductivity: lastThirtyDayProductivity,
                thisYearProductivity: thisYearProductivity,
                allTimeProductivity: allTimeProductivity,
                lastSevenDayModelUsage: Self.topModelUsage(
                    transcription: lastSevenDayTranscriptionUsage,
                    enhancement: lastSevenDayEnhancementUsage
                ),
                lastThirtyDayModelUsage: Self.topModelUsage(
                    transcription: lastThirtyDayTranscriptionUsage,
                    enhancement: lastThirtyDayEnhancementUsage
                ),
                thisYearModelUsage: Self.topModelUsage(
                    transcription: thisYearTranscriptionUsage,
                    enhancement: thisYearEnhancementUsage
                ),
                allTimeModelUsage: Self.topModelUsage(
                    transcription: allTimeTranscriptionUsage,
                    enhancement: allTimeEnhancementUsage
                ),
                lastSevenDayPeakHours: Self.peakHoursSummary(from: lastSevenDayPeakHours),
                lastThirtyDayPeakHours: Self.peakHoursSummary(from: lastThirtyDayPeakHours),
                thisYearPeakHours: Self.peakHoursSummary(from: thisYearPeakHours),
                allTimePeakHours: Self.peakHoursSummary(from: allTimePeakHours)
            )
        }

        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func monthlyProductivityPoints(
        from startDate: Date,
        through endDate: Date,
        calendar: Calendar,
        wordsByMonth: [Date: Int] = [:]
    ) -> [DashboardProductivityPoint] {
        let startMonth = startOfMonth(for: startDate, calendar: calendar)
        let endMonth = startOfMonth(for: endDate, calendar: calendar)
        guard let monthCount = calendar.dateComponents([.month], from: startMonth, to: endMonth).month else {
            return []
        }

        let labelFormatter = DateFormatter()
        labelFormatter.calendar = calendar
        labelFormatter.locale = .current
        labelFormatter.dateFormat = "MMM"

        let accessibilityFormatter = DateFormatter()
        accessibilityFormatter.calendar = calendar
        accessibilityFormatter.locale = .current
        accessibilityFormatter.dateFormat = "MMMM yyyy"

        return (0...max(monthCount, 0)).compactMap { offset in
            guard let date = calendar.date(byAdding: .month, value: offset, to: startMonth) else {
                return nil
            }

            return DashboardProductivityPoint(
                date: startOfMonth(for: date, calendar: calendar),
                label: labelFormatter.string(from: date),
                accessibilityLabel: accessibilityFormatter.string(from: date),
                words: wordsByMonth[startOfMonth(for: date, calendar: calendar), default: 0]
            )
        }
    }

    private static func productivityPoints(
        dayCount: Int,
        now: Date,
        calendar: Calendar,
        labelStyle: DashboardProductivityLabelStyle
    ) -> [DashboardProductivityPoint] {
        guard let startDate = calendar.date(byAdding: .day, value: -(dayCount - 1), to: calendar.startOfDay(for: now)) else {
            return []
        }

        let labelFormatter = DateFormatter()
        labelFormatter.calendar = calendar
        labelFormatter.locale = .current
        labelFormatter.dateFormat = labelStyle.dateFormat

        let accessibilityFormatter = DateFormatter()
        accessibilityFormatter.calendar = calendar
        accessibilityFormatter.locale = .current
        accessibilityFormatter.dateStyle = .medium

        return (0..<dayCount).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: startDate) else {
                return nil
            }

            return DashboardProductivityPoint(
                date: calendar.startOfDay(for: date),
                label: labelFormatter.string(from: date),
                accessibilityLabel: accessibilityFormatter.string(from: date)
            )
        }
    }

    private static func topModelUsage(
        transcription: [String: DashboardModelUsageAccumulator],
        enhancement: [String: DashboardModelUsageAccumulator]
    ) -> [DashboardModelUsageSummary] {
        let transcriptionSummaries = transcription.map { name, accumulator in
            accumulator.summary(kind: .transcription, name: name)
        }
        let enhancementSummaries = enhancement.map { name, accumulator in
            accumulator.summary(kind: .enhancement, name: name)
        }

        return Array(transcriptionSummaries.sortedForDashboardDisplay().prefix(3)) +
            Array(enhancementSummaries.sortedForDashboardDisplay().prefix(3))
    }

    private static func addModelUsage(
        for metric: SessionMetric,
        transcriptionUsage: inout [String: DashboardModelUsageAccumulator],
        enhancementUsage: inout [String: DashboardModelUsageAccumulator]
    ) {
        if let modelName = sanitizedModelName(metric.transcriptionModelName),
           let transcriptionDuration = metric.transcriptionDuration,
           transcriptionDuration > 0 {
            transcriptionUsage[modelName, default: DashboardModelUsageAccumulator()].add(
                duration: transcriptionDuration
            )
        }

        if let modelName = sanitizedModelName(metric.aiEnhancementModelName),
           let enhancementDuration = metric.enhancementDuration,
           enhancementDuration > 0 {
            enhancementUsage[modelName, default: DashboardModelUsageAccumulator()].add(
                duration: enhancementDuration
            )
        }
    }

    private static func addPeakHour(
        for metric: SessionMetric,
        hour: Int,
        to peakHours: inout [Int: DashboardPeakHourAccumulator]
    ) {
        peakHours[hour, default: DashboardPeakHourAccumulator()].add(words: metric.wordCount)
    }

    private static func peakHoursSummary(from peakHours: [Int: DashboardPeakHourAccumulator]) -> DashboardPeakHoursSummary {
        let hourlyActivity = (0..<24).map { hour in
            peakHours[hour, default: DashboardPeakHourAccumulator()].point(hour: hour)
        }

        var bestStartHour = 0
        var bestWordCount = 0
        var bestSessionCount = 0

        for startHour in 0..<24 {
            let first = peakHours[startHour, default: DashboardPeakHourAccumulator()]
            let second = peakHours[(startHour + 1) % 24, default: DashboardPeakHourAccumulator()]
            let windowWordCount = first.wordCount + second.wordCount
            let windowSessionCount = first.sessionCount + second.sessionCount

            if windowWordCount > bestWordCount ||
                (windowWordCount == bestWordCount && windowSessionCount > bestSessionCount) {
                bestStartHour = startHour
                bestWordCount = windowWordCount
                bestSessionCount = windowSessionCount
            }
        }

        return DashboardPeakHoursSummary(
            startHour: bestStartHour,
            endHour: (bestStartHour + 2) % 24,
            wordCount: bestWordCount,
            sessionCount: bestSessionCount,
            hourlyActivity: hourlyActivity
        )
    }
}

private func startOfMonth(for date: Date, calendar: Calendar) -> Date {
    calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
}

private enum DashboardProductivityLabelStyle {
    case weekday
    case dayOfMonth

    var dateFormat: String {
        switch self {
        case .weekday: return "E"
        case .dayOfMonth: return "d"
        }
    }
}

private struct DashboardModelUsageAccumulator {
    var sessionCount = 0
    var totalDuration: TimeInterval = 0

    mutating func add(duration: TimeInterval) {
        sessionCount += 1
        totalDuration += duration
    }

    func summary(kind: DashboardModelUsageKind, name: String) -> DashboardModelUsageSummary {
        DashboardModelUsageSummary(
            kind: kind,
            name: name,
            sessionCount: sessionCount,
            averageDuration: sessionCount > 0 ? totalDuration / Double(sessionCount) : nil
        )
    }
}

private struct DashboardPeakHourAccumulator {
    var wordCount = 0
    var sessionCount = 0

    mutating func add(words: Int) {
        wordCount += words
        sessionCount += 1
    }

    func point(hour: Int) -> DashboardHourlyActivityPoint {
        DashboardHourlyActivityPoint(
            hour: hour,
            wordCount: wordCount,
            sessionCount: sessionCount
        )
    }
}

private func sanitizedModelName(_ name: String?) -> String? {
    guard let name else {
        return nil
    }

    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
