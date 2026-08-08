import Charts
import SwiftUI

/// The drill-in for a single insight: the figure, what it means, and the chart that shows the
/// distribution behind it.
///
/// The overview answers "how am I doing". This answers "why is that the number", which is the only
/// question a summary figure can provoke and the one a scoreboard never lets you ask.
struct InsightDetailView: View {
    let topic: InsightTopic
    let insights: DashboardInsightBundle
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                content
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)

            Text(topic.title)
                .font(.system(size: 18, weight: .semibold))

            Spacer()

            Text("Last 30 days")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch topic {
        case .pace: paceDetail
        case .wait: waitDetail
        case .reliability: reliabilityDetail
        case .enhancement: enhancementDetail
        case .destinations: destinationsDetail
        case .models: modelsDetail
        }
    }

    // MARK: - Pace

    private var paceDetail: some View {
        let dictation = insights.dictation
        return VStack(alignment: .leading, spacing: 16) {
            InsightHeadline(
                value: dictation.speakingWordsPerMinute.map { String(format: "%.0f", $0) } ?? "—",
                unit: "words per minute",
                explanation: String(
                    localized:
                        "Measured from your own takes: total words divided by total seconds spoken. This is where the time saving actually comes from — it is not an estimate."
                )
            )

            if let versus = dictation.speedVersusTyping {
                InsightComparisonBar(
                    left: ("Typing", DictationInsights.referenceTypingWordsPerMinute),
                    right: ("You, speaking", dictation.speakingWordsPerMinute ?? 0),
                    footnote: String(
                        format: String(
                            localized:
                                "About %.1f× faster. Typing speed is a rough average, not your own — only the speaking figure is measured."
                        ), versus)
                )
            }

            InsightFactRow(
                label: "Typical take",
                value: dictation.typicalTakeDuration?.formatTiming() ?? "—",
                note: String(localized: "Median, so one long recording doesn't skew it"))
            InsightFactRow(
                label: "Longest take",
                value: dictation.longestTakeDuration?.formatTiming() ?? "—",
                note: String(localized: "Very long takes are harder to correct if they go wrong"))
            InsightFactRow(
                label: "Days used",
                value: String(
                    format: String(localized: "%lld of %lld"),
                    Int64(dictation.activeDays), Int64(dictation.windowDays)),
                note: dictation.currentStreak >= 2
                    ? String(
                        format: String(localized: "%lld-day streak running"),
                        Int64(dictation.currentStreak))
                    : String(localized: "Days with at least one take"))
        }
    }

    // MARK: - Wait

    private var waitDetail: some View {
        let dictation = insights.dictation
        let share = dictation.enhancementShareOfWait
        return VStack(alignment: .leading, spacing: 16) {
            InsightHeadline(
                value: dictation.typicalWaitDuration?.formatTiming() ?? "—",
                unit: "from finishing to text landing",
                explanation: waitAdvice(share: share)
            )

            if let share {
                Chart {
                    BarMark(x: .value("Share", (1 - share) * 100))
                        .foregroundStyle(by: .value("Stage", "Transcription"))
                    BarMark(x: .value("Share", share * 100))
                        .foregroundStyle(by: .value("Stage", "Enhancement"))
                }
                .chartXScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                        AxisValueLabel {
                            if let percent = value.as(Int.self) { Text("\(percent)%") }
                        }
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 90)
            }

            InsightFactRow(
                label: "Re-dictated",
                value: insights.redictation.rate.map { String(format: "%.0f%%", $0 * 100) } ?? "—",
                note: String(
                    localized:
                        "Takes followed by another within 30 seconds — usually a sign the first one came out wrong"
                ))
        }
    }

    private func waitAdvice(share: Double?) -> String {
        guard let share else {
            return String(localized: "How long you wait after speaking before the text appears.")
        }
        if share >= 0.6 {
            return String(
                format: String(
                    localized:
                        "%.0f%% of the wait is the AI enhancement pass. A faster transcription model won't help much here — a faster or smaller enhancement model will."
                ), share * 100)
        }
        if share <= 0.2 {
            return String(
                localized:
                    "Almost all of the wait is transcription. A faster model, or a local one, is the lever that matters."
            )
        }
        return String(
            format: String(
                localized: "Split roughly %.0f%% transcription and %.0f%% enhancement."),
            (1 - share) * 100, share * 100)
    }

    // MARK: - Reliability

    private var reliabilityDetail: some View {
        let reliability = insights.reliability
        return VStack(alignment: .leading, spacing: 16) {
            InsightHeadline(
                value: reliability.successRate.map { String(format: "%.1f%%", $0 * 100) } ?? "—",
                unit: "of attempted takes completed",
                explanation: String(
                    localized:
                        "Cancellations are left out of this figure. Abandoning a take is a decision, not a failure, so it gets its own number below."
                )
            )

            InsightFactRow(
                label: "Completed", value: "\(reliability.completed)",
                note: String(localized: "Produced text"))
            InsightFactRow(
                label: "Failed", value: "\(reliability.failed)",
                note: String(localized: "Errored before producing anything"))
            InsightFactRow(
                label: "Cancelled", value: "\(reliability.canceled)",
                note: reliability.cancelRate.map {
                    String(format: String(localized: "%.0f%% of everything started"), $0 * 100)
                } ?? String(localized: "Stopped deliberately"))

            if insights.dictionary.hasData {
                Divider()
                InsightFactRow(
                    label: "Dictionary",
                    value: insights.dictionary.hitRate.map { String(format: "%.0f%%", $0 * 100) }
                        ?? "—",
                    note: String(
                        format: String(localized: "of takes had a replacement fire (%lld in total)"),
                        Int64(insights.dictionary.totalHits)))
            }
        }
    }

    // MARK: - Enhancement

    private var enhancementDetail: some View {
        let enhancement = insights.enhancement
        return VStack(alignment: .leading, spacing: 16) {
            InsightHeadline(
                value: enhancement.medianChangeRatio.map { String(format: "%.0f%%", $0 * 100) }
                    ?? "—",
                unit: "of your words rewritten",
                explanation: enhancementAdvice(enhancement)
            )

            InsightFactRow(
                label: "Takes enhanced",
                value: "\(enhancement.enhancedTakes)",
                note: enhancement.enhancementUsageRate.map {
                    String(format: String(localized: "%.0f%% of all takes"), $0 * 100)
                } ?? "")
            InsightFactRow(
                label: "Barely changed",
                value: "\(enhancement.untouchedTakes)",
                note: String(
                    localized: "Takes where the pass rewrote less than 2% — it ran for nothing"))

            if !insights.library.prompts.isEmpty {
                Divider()
                Text("Prompts you actually use")
                    .font(.system(size: 12, weight: .medium))
                ForEach(insights.library.prompts.prefix(5)) { prompt in
                    InsightFactRow(
                        label: LocalizedStringKey(prompt.name),
                        value: "\(prompt.takes)",
                        note: "")
                }
            }
        }
    }

    private func enhancementAdvice(_ enhancement: EnhancementImpactSummary) -> String {
        guard let ratio = enhancement.medianChangeRatio else {
            return String(
                localized: "How much the AI pass changes what you actually said.")
        }
        if ratio < 0.05 {
            return String(
                localized:
                    "The pass is barely touching your text. You are paying its wait and its cost for very little — worth checking whether the prompt is doing anything."
            )
        }
        if ratio > 0.5 {
            return String(
                localized:
                    "The pass is rewriting more than half of what you say. That is a lot of trust to place in it — worth reading a few results against the originals."
            )
        }
        return String(
            localized:
                "A moderate rewrite: tidying and restructuring without replacing what you said.")
    }

    // MARK: - Destinations

    private var destinationsDetail: some View {
        let destinations = insights.destinations
        let total = max(destinations.totalWords, 1)
        return VStack(alignment: .leading, spacing: 16) {
            InsightHeadline(
                value: destinations.destinations.first.map {
                    InsightFormatting.appName(for: $0.bundleIdentifier)
                } ?? "—",
                unit: "takes most of your words",
                explanation: String(
                    localized:
                        "Where the text actually landed. Useful for deciding which apps deserve their own mode — a destination you dictate into constantly is a mode waiting to be made."
                )
            )

            ForEach(destinations.destinations.prefix(8)) { destination in
                HStack(spacing: 10) {
                    if let icon = InsightFormatting.appIcon(for: destination.bundleIdentifier) {
                        Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                    }
                    Text(InsightFormatting.appName(for: destination.bundleIdentifier))
                        .font(.system(size: 12))

                    Spacer(minLength: 8)

                    ProgressView(value: Double(destination.words), total: Double(total))
                        .progressViewStyle(.linear)
                        .frame(width: 120)

                    Text(
                        String(
                            format: "%.0f%%", Double(destination.words) / Double(total) * 100)
                    )
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
                }
            }

            if destinations.unattributedTakes > 0 {
                Text(
                    String(
                        format: String(
                            localized: "%lld takes have no destination recorded — they predate this."
                        ), Int64(destinations.unattributedTakes))
                )
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Models

    private var modelsDetail: some View {
        VStack(alignment: .leading, spacing: 16) {
            InsightHeadline(
                value: "\(insights.models.models.count)",
                unit: "models used",
                explanation: String(
                    localized:
                        "Speed and outcome together, because either one alone misleads — the fastest model is a poor choice if a share of its takes have to be redone."
                )
            )

            if !insights.models.models.isEmpty {
                Chart(insights.models.models) { model in
                    BarMark(
                        x: .value("Speed", model.averageSpeedFactor ?? 0),
                        y: .value("Model", model.name)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                    .annotation(position: .trailing) {
                        if let speed = model.averageSpeedFactor {
                            Text(String(format: "%.1f×", speed))
                                .font(.system(size: 10))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .chartXAxisLabel(String(localized: "× realtime"))
                .frame(height: CGFloat(insights.models.models.count) * 38 + 40)
            }

            ForEach(insights.models.models) { model in
                InsightFactRow(
                    label: LocalizedStringKey(model.name),
                    value: model.successRate.map { String(format: "%.0f%%", $0 * 100) } ?? "—",
                    note: {
                        var parts = [
                            String(format: String(localized: "%lld takes"), Int64(model.takes))
                        ]
                        if let undo = model.undoRate, undo > 0 {
                            parts.append(
                                String(format: String(localized: "%.0f%% undone"), undo * 100))
                        }
                        return parts.joined(separator: " · ")
                    }())
            }

            if insights.library.retainedAudioFiles > 0 {
                Divider()
                InsightFactRow(
                    label: "Audio kept",
                    value: InsightFormatting.bytes(insights.library.retainedAudioBytes),
                    note: String(
                        format: String(localized: "across %lld recordings"),
                        Int64(insights.library.retainedAudioFiles)))
            }
        }
    }
}

// MARK: - Pieces

private struct InsightHeadline: View {
    let value: String
    let unit: LocalizedStringKey
    let explanation: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value)
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Text(explanation)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DashboardInsightCardBackground())
    }
}

private struct InsightFactRow: View {
    let label: LocalizedStringKey
    let value: String
    let note: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 12, weight: .medium))
                if !note.isEmpty {
                    Text(note)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
        }
        .padding(.vertical, 6)
    }
}

/// Two bars against a shared scale. Used only where the comparison is the point.
private struct InsightComparisonBar: View {
    let left: (LocalizedStringKey, Double)
    let right: (LocalizedStringKey, Double)
    let footnote: String

    private var scale: Double { max(left.1, right.1, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            bar(label: left.0, value: left.1, tint: Color.secondary.opacity(0.45))
            bar(label: right.0, value: right.1, tint: Color.accentColor)

            Text(footnote)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DashboardInsightCardBackground())
    }

    private func bar(label: LocalizedStringKey, value: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f wpm", value))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
            }
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(tint)
                    .frame(width: max(4, geo.size.width * (value / scale)))
            }
            .frame(height: 8)
        }
    }
}
