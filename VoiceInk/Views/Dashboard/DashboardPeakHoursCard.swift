import SwiftUI

struct DashboardPeakHoursCard: View {
    private static let cornerRadius: CGFloat = 16
    private static let cardHeight: CGFloat = 196

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
        .frame(maxWidth: .infinity, minHeight: Self.cardHeight, maxHeight: Self.cardHeight, alignment: .topLeading)
        .background(AppCardBackground(cornerRadius: Self.cornerRadius))
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

            Text(canShowPattern ? windowText : "--")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Text.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
    }

    private var windowText: String {
        formattedHourRange(from: summary.startHour, to: summary.endHour)
    }

    private var accessibilityValue: String {
        if isLocked {
            return "Continue using VoiceInk to unlock peak hours."
        }

        guard summary.hasData else {
            return "No hourly pattern yet."
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
        return "\(formattedHour(startHour)) to \(formattedHour(endHour))"
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
                            Capsule(style: .continuous)
                                .fill(barStyle(for: point))
                                .frame(maxWidth: .infinity)
                                .frame(height: barHeight(for: point, in: geometry.size))
                                .shadow(
                                    color: isPeakHour(point.hour) && hasData ? peakTint.opacity(0.18) : Color.clear,
                                    radius: 4,
                                    y: 1
                                )
                                .accessibilityHidden(true)
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
        let opacity = gradientOpacity(for: point.hour)

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
            return 5
        }

        let normalized = min(max(CGFloat(point.wordCount) / CGFloat(maxWords), 0), 1)
        return max(8, normalized * max(size.height - 10, 1))
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

    private func gradientOpacity(for hour: Int) -> CGFloat {
        guard hasData else {
            return 0.10
        }

        let firstHour = normalizedHour(peakStartHour)
        let secondHour = normalizedHour(peakStartHour + 1)
        let distance = min(circularDistance(from: hour, to: firstHour), circularDistance(from: hour, to: secondHour))
        let falloff = max(0, 1 - CGFloat(distance) / 7)
        let hasActivity = (points.first { normalizedHour($0.hour) == normalizedHour(hour) }?.wordCount ?? 0) > 0
        let base: CGFloat = hasActivity ? 0.16 : 0.07

        if distance == 0 {
            return 0.88
        }

        return base + CGFloat(pow(Double(falloff), 2.0)) * 0.52
    }

    private func circularDistance(from hour: Int, to targetHour: Int) -> Int {
        let rawDistance = abs(normalizedHour(hour) - normalizedHour(targetHour))
        return min(rawDistance, 24 - rawDistance)
    }

    private func normalizedHour(_ hour: Int) -> Int {
        ((hour % 24) + 24) % 24
    }
}
