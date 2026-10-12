import Foundation

enum Formatters {
    static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    static func formattedNumber(_ value: Int) -> String {
        numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func formattedCompactNumber(_ value: Int) -> String {
        guard value >= 1000 else {
            return "\(value)"
        }

        var divisor: Double = value >= 1_000_000 ? 1_000_000 : 1000
        var suffix = value >= 1_000_000 ? "M" : "K"
        let compactValue = Double(value) / divisor
        var roundedValue = (compactValue * 10).rounded() / 10

        if suffix == "K", roundedValue >= 1000 {
            divisor = 1_000_000
            suffix = "M"
            roundedValue = ((Double(value) / divisor) * 10).rounded() / 10
        }

        if roundedValue.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(roundedValue))\(suffix)"
        }

        return String(format: "%.1f%@", roundedValue, suffix)
    }

    static func formattedAxisValue(_ value: Int) -> String {
        value >= 1000 ? formattedCompactNumber(value) : "\(value)"
    }

    static func localizedHourFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("j")
        return formatter
    }

    static func formattedCompactHoursAndMinutes(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, Int((interval / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours >= 1000 {
            return "\(formattedCompactNumber(hours)) h"
        }

        if hours > 0, minutes > 0 {
            return "\(hours)h \(minutes)m"
        }

        if hours > 0 {
            return "\(hours)h"
        }

        return "\(minutes)m"
    }

    static func formattedSavedTime(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, Int((interval / 60).rounded()))
        let hours = totalMinutes / 60

        guard hours >= 1000 else {
            return formattedCompactHoursAndMinutes(interval)
        }

        return "\(formattedCompactNumber(hours)) \(String(localized: "hours"))"
    }

    static func roundedChartMaximum(for value: Int) -> Int {
        guard value > 0 else {
            return 1000
        }

        let target = Double(value) * 1.12
        let magnitude = pow(10, floor(log10(target)))
        let normalized = target / magnitude
        let step: Double

        switch normalized {
        case ...1:
            step = 1
        case ...2:
            step = 2
        case ...5:
            step = 5
        default:
            step = 10
        }

        return Int(step * magnitude)
    }

    static func formattedDuration(
        _ interval: TimeInterval, style: DateComponentsFormatter.UnitsStyle, fallback: String = "-"
    ) -> String {
        guard interval > 0 else { return fallback }
        let formatter = DateComponentsFormatter()
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = style
        formatter.allowedUnits = interval >= 3600 ? [.hour, .minute] : [.minute, .second]
        return formatter.string(from: interval) ?? fallback
    }

    static func formattedPreciseDuration(_ interval: TimeInterval, fallback: String = "-") -> String {
        guard interval > 0 else {
            return fallback
        }

        let roundedTenths = Int((interval * 10).rounded())

        if roundedTenths < 600 {
            return String(format: "%.1f sec", Double(roundedTenths) / 10)
        }

        if roundedTenths < 36_000 {
            let minutes = roundedTenths / 600
            let seconds = Double(roundedTenths % 600) / 10
            return "\(minutes)m \(String(format: "%.1f", seconds))s"
        }

        let totalMinutes = roundedTenths / 600
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return "\(hours)h \(minutes)m"
    }
}
