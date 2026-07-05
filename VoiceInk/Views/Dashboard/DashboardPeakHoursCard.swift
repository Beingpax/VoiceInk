import SwiftUI

struct DashboardPeakHoursCard: View {
    let summary: DashboardPeakHoursSummary
    var isLocked = false

    private var maxHourlyWords: Int {
        max(summary.hourlyActivity.map(\.wordCount).max() ?? 0, 1)
    }

    private var canShowPattern: Bool {
        !isLocked && summary.hasData
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 16) {
                header

                DashboardPeakHoursHistogram(
                    points: summary.hourlyActivity,
                    maxWords: maxHourlyWords,
                    peakStartHour: summary.startHour,
                    hasData: canShowPattern
                )
            }
            .blur(radius: isLocked ? 2 : 0)
            .opacity(isLocked ? 0.42 : 1)

            if isLocked {
                lockedOverlay
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 196, maxHeight: 196, alignment: .topLeading)
        .background(DashboardInsightCardBackground(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Peak dictation hours")
        .accessibilityValue(accessibilityValue)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Peak Dictation Hours")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Text.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.84)

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.Text.secondary.opacity(0.78))

                Text(canShowPattern ? windowText : "--")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Text.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
        }
    }

    private var windowText: String {
        formattedHourRange(from: summary.startHour, to: summary.endHour)
    }

    private var accessibilityValue: String {
        if isLocked {
            return String(localized: "Continue using VoiceInk to unlock peak hours.")
        }

        guard summary.hasData else {
            return String(localized: "No hourly pattern yet.")
        }

        return windowText
    }

    private var lockedOverlay: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppTheme.Accent.primary)
                .frame(width: 34, height: 34)
                .background(AppTheme.Accent.fill)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            Text("Continue using VoiceInk to unlock peak hours.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.Text.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 260)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func formattedHourRange(from startHour: Int, to endHour: Int) -> String {
        String(
            format: String(localized: "%@ to %@"),
            formattedHour(startHour),
            formattedHour(endHour)
        )
    }

    private func formattedHour(_ hour: Int) -> String {
        "\(displayHour(hour)) \(hourSuffix(hour))"
    }

    private func displayHour(_ hour: Int) -> Int {
        let hour = ((hour % 24) + 24) % 24
        return hour % 12 == 0 ? 12 : hour % 12
    }

    private func hourSuffix(_ hour: Int) -> String {
        let hour = ((hour % 24) + 24) % 24
        return hour < 12 ? "AM" : "PM"
    }
}

private struct DashboardPeakHoursHistogram: View {
    private let peakTint = AppTheme.Accent.strong
    private let peakTintSoft = AppTheme.Accent.primary.opacity(0.46)

    let points: [DashboardHourlyActivityPoint]
    let maxWords: Int
    let peakStartHour: Int
    let hasData: Bool

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    baseline
                        .frame(width: geometry.size.width)
                        .position(x: geometry.size.width / 2, y: geometry.size.height - 1)

                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(points) { point in
                            ZStack(alignment: .bottom) {
                                Capsule(style: .continuous)
                                    .fill(AppTheme.Border.subtle.opacity(hasData ? 0.13 : 0.08))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                                Capsule(style: .continuous)
                                    .fill(barStyle(for: point))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: barHeight(for: point, in: geometry.size))
                                    .shadow(
                                        color: isPeakHour(point.hour) && hasData ? peakTint.opacity(0.22) : Color.clear,
                                        radius: 5,
                                        y: 1
                                    )
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .frame(height: 104)

            HStack {
                axisLabel("12 AM")
                Spacer(minLength: 0)
                axisLabel("6 AM")
                Spacer(minLength: 0)
                axisLabel("12 PM")
                Spacer(minLength: 0)
                axisLabel("6 PM")
                Spacer(minLength: 0)
                axisLabel("12 AM")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hourly dictation activity")
    }

    private var baseline: some View {
        Rectangle()
            .fill(AppTheme.Border.subtle.opacity(0.55))
            .frame(height: 1)
    }

    private func barStyle(for point: DashboardHourlyActivityPoint) -> AnyShapeStyle {
        let opacity = barOpacity(for: point)

        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    peakTintSoft.opacity(opacity),
                    peakTint.opacity(opacity * 0.94)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func barHeight(for point: DashboardHourlyActivityPoint, in size: CGSize) -> CGFloat {
        guard hasData, maxWords > 0, point.wordCount > 0 else {
            return 3
        }

        let availableHeight = max(size.height - 10, 1)
        return max(4, availableHeight * (0.40 + (emphasizedActivity(for: point) * 0.60)))
    }

    private func axisLabel(_ label: LocalizedStringKey) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(AppTheme.Text.secondary)
            .lineLimit(1)
    }

    private func isPeakHour(_ hour: Int) -> Bool {
        let hour = normalizedHour(hour)
        let firstHour = normalizedHour(peakStartHour)
        let secondHour = normalizedHour(firstHour + 1)
        return hour == firstHour || hour == secondHour
    }

    private func barOpacity(for point: DashboardHourlyActivityPoint) -> CGFloat {
        guard hasData else {
            return 0.10
        }

        guard point.wordCount > 0, maxWords > 0 else {
            return 0.10
        }

        let normalized = emphasizedActivity(for: point)
        let peakBoost: CGFloat = isPeakHour(point.hour) ? 0.16 : 0

        return min(0.92, 0.22 + (normalized * 0.50) + peakBoost)
    }

    private func emphasizedActivity(for point: DashboardHourlyActivityPoint) -> CGFloat {
        CGFloat(pow(Double(relativeActivity(for: point)), 0.82))
    }

    private func relativeActivity(for point: DashboardHourlyActivityPoint) -> CGFloat {
        let wordScore = relativeScore(
            value: CGFloat(point.wordCount),
            values: points.map { CGFloat($0.wordCount) }
        )

        let activeDayScore = relativeScore(
            value: CGFloat(point.activeDayCount),
            values: points.map { CGFloat($0.activeDayCount) }
        )
        let audioDurationScore = relativeScore(
            value: CGFloat(point.audioDuration),
            values: points.map { CGFloat($0.audioDuration) }
        )

        return (wordScore * 0.64) + (activeDayScore * 0.20) + (audioDurationScore * 0.16)
    }

    private func relativeScore(value: CGFloat, values: [CGFloat]) -> CGFloat {
        let activeValues = values.filter { $0 > 0 }
        guard
            value > 0,
            let minValue = activeValues.min(),
            let maxValue = activeValues.max()
        else {
            return 0
        }

        guard maxValue > minValue else {
            return 0.5
        }

        return min(max((value - minValue) / (maxValue - minValue), 0), 1)
    }

    private func normalizedHour(_ hour: Int) -> Int {
        ((hour % 24) + 24) % 24
    }
}
