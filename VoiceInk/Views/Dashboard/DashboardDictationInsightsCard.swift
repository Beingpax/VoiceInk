import SwiftUI

/// How you actually dictate, over the last 30 days.
///
/// The rest of the dashboard counts things: words, minutes, sessions. Those go up, and knowing they
/// went up changes nothing. Every row here exists because there is a decision behind it — each one
/// pairs a measured figure with the thing it should make you consider.
///
/// Nothing appears until there are enough takes to mean something. A dashboard that states noise
/// confidently teaches people to distrust the parts that aren't.
struct DashboardDictationInsightsCard: View {
    let insights: DictationInsights

    var body: some View {
        if insights.hasData {
            VStack(alignment: .leading, spacing: 14) {
                header

                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 {
                            Divider().opacity(0.5)
                        }
                        InsightRow(row: row)
                    }
                }
            }
            .padding(20)
            .background(DashboardInsightCardBackground())
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("How you dictate")
                .font(.system(size: 15, weight: .semibold))

            Text(
                String(
                    format: String(localized: "Last 30 days · %lld takes"),
                    Int64(insights.sessionCount)
                )
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Rows

    private struct Row {
        let icon: String
        let title: LocalizedStringKey
        let value: String
        /// The reason the number is here at all.
        let meaning: String
    }

    private var rows: [Row] {
        var rows: [Row] = []

        if let pace = insights.speakingWordsPerMinute, let versus = insights.speedVersusTyping {
            rows.append(
                Row(
                    icon: "waveform",
                    title: "Speaking pace",
                    value: String(
                        format: String(localized: "%.0f words/min"), pace),
                    meaning: String(
                        format: String(
                            localized: "About %.1f× typing speed — where the time saving comes from."
                        ),
                        versus
                    )
                )
            )
        }

        if let typical = insights.typicalTakeDuration {
            var meaning = String(
                localized: "Median, so one long recording doesn't skew it.")
            if let longest = insights.longestTakeDuration, longest > typical * 3 {
                meaning = String(
                    format: String(localized: "Your longest ran %@ — worth splitting takes that big."),
                    longest.formatTiming()
                )
            }
            rows.append(
                Row(
                    icon: "clock",
                    title: "Typical take",
                    value: typical.formatTiming(),
                    meaning: meaning
                )
            )
        }

        if let wait = insights.typicalWaitDuration {
            var meaning = String(localized: "Time between finishing and the text landing.")
            // The actionable half: pointing at the wrong lever wastes a model change.
            if let share = insights.enhancementShareOfWait {
                if share >= 0.6 {
                    meaning = String(
                        format: String(
                            localized:
                                "%.0f%% of it is AI enhancement — a faster transcription model won't help much."
                        ), share * 100)
                } else if share <= 0.2 {
                    meaning = String(
                        localized:
                            "Almost all transcription — a faster model is the lever here.")
                } else {
                    meaning = String(
                        format: String(localized: "%.0f%% transcription, %.0f%% enhancement."),
                        (1 - share) * 100, share * 100)
                }
            }
            rows.append(
                Row(icon: "hourglass", title: "Typical wait", value: wait.formatTiming(), meaning: meaning)
            )
        }

        if let mode = insights.topModeName, let share = insights.topModeShare {
            var meaning = String(
                format: String(localized: "Across %lld modes, weighted by words."),
                Int64(insights.modeCount))
            if insights.modeCount > 1, share >= 0.9 {
                meaning = String(
                    format: String(
                        localized:
                            "Carries %.0f%% of your words. The other %lld are barely earning their shortcut."
                    ), share * 100, Int64(insights.modeCount - 1))
            } else if insights.modeCount > 1 {
                meaning = String(
                    format: String(localized: "%.0f%% of your words, across %lld modes."),
                    share * 100, Int64(insights.modeCount))
            }
            rows.append(
                Row(icon: "slider.horizontal.3", title: "Busiest mode", value: mode, meaning: meaning)
            )
        }

        if insights.activeDays > 0 {
            var meaning = String(
                format: String(localized: "Out of the last %lld days."), Int64(insights.windowDays))
            if insights.currentStreak >= 2 {
                meaning = String(
                    format: String(localized: "%lld-day streak running."),
                    Int64(insights.currentStreak))
            }
            rows.append(
                Row(
                    icon: "calendar",
                    title: "Days used",
                    value: String(
                        format: String(localized: "%lld of %lld"),
                        Int64(insights.activeDays), Int64(insights.windowDays)),
                    meaning: meaning
                )
            )
        }

        return rows
    }

    private struct InsightRow: View {
        let row: Row

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: row.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Text(row.meaning)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Text(row.value)
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 10)
        }
    }
}
