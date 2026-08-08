import SwiftUI

/// Which detail screen a summary card opens.
enum InsightTopic: String, Identifiable, CaseIterable {
    case pace
    case wait
    case reliability
    case enhancement
    case destinations
    case models

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .pace: return "Speaking pace"
        case .wait: return "The wait"
        case .reliability: return "Reliability"
        case .enhancement: return "Enhancement"
        case .destinations: return "Where words go"
        case .models: return "Models"
        }
    }

    var icon: String {
        switch self {
        case .pace: return "waveform"
        case .wait: return "hourglass"
        case .reliability: return "checkmark.seal"
        case .enhancement: return "sparkles"
        case .destinations: return "arrow.right.doc.on.clipboard"
        case .models: return "cpu"
        }
    }
}

/// A single figure, and the sentence that makes it mean something.
///
/// Every card carries both. A number on its own is a scoreboard entry; the line underneath is the
/// reason it is on screen at all, and if a card cannot produce one it should not be here.
struct InsightSummaryCard: View {
    let topic: InsightTopic
    let value: String
    let caption: String
    /// Cards with nothing behind them yet still appear, greyed, saying what they are waiting for.
    /// Hiding them makes the dashboard's shape change as data arrives, which is disorienting.
    var isPending: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: topic.icon)
                        .font(.system(size: 11, weight: .medium))
                    Text(topic.title)
                        .font(.system(size: 11, weight: .medium))
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .opacity(isHovering ? 0.6 : 0.25)
                }
                .foregroundStyle(.secondary)

                Text(value)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isPending ? .tertiary : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .background(DashboardInsightCardBackground())
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isHovering ? 0.12 : 0), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isPending)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

/// The overview: six figures, each a door into its own detail.
///
/// Chosen over one long scroll because the set will keep growing, and over tabs because the
/// summary itself is the most useful screen — most visits end here, having answered the question
/// in one glance.
struct InsightOverviewGrid: View {
    let insights: DashboardInsightBundle
    let onSelect: (InsightTopic) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 210), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            paceCard
            waitCard
            reliabilityCard
            enhancementCard
            destinationsCard
            modelsCard
        }
    }

    // MARK: - Cards

    private var paceCard: some View {
        let dictation = insights.dictation
        return InsightSummaryCard(
            topic: .pace,
            value: dictation.speakingWordsPerMinute.map { String(format: "%.0f wpm", $0) } ?? "—",
            caption: dictation.speedVersusTyping.map {
                String(format: String(localized: "About %.1f× typing speed"), $0)
            } ?? String(localized: "Needs a few more takes"),
            isPending: !dictation.hasData,
            action: { onSelect(.pace) }
        )
    }

    private var waitCard: some View {
        let dictation = insights.dictation
        return InsightSummaryCard(
            topic: .wait,
            value: dictation.typicalWaitDuration?.formatTiming() ?? "—",
            caption: dictation.enhancementShareOfWait.map {
                String(format: String(localized: "%.0f%% of it is enhancement"), $0 * 100)
            } ?? String(localized: "Time from finishing to text landing"),
            isPending: dictation.typicalWaitDuration == nil,
            action: { onSelect(.wait) }
        )
    }

    private var reliabilityCard: some View {
        let reliability = insights.reliability
        return InsightSummaryCard(
            topic: .reliability,
            value: reliability.successRate.map { String(format: "%.1f%%", $0 * 100) } ?? "—",
            caption: reliability.failed > 0
                ? String(
                    format: String(localized: "%lld failed of %lld attempted"),
                    Int64(reliability.failed), Int64(reliability.attempted))
                : String(localized: "No failures in the last 30 days"),
            isPending: !reliability.hasData,
            action: { onSelect(.reliability) }
        )
    }

    private var enhancementCard: some View {
        let enhancement = insights.enhancement
        return InsightSummaryCard(
            topic: .enhancement,
            value: enhancement.medianChangeRatio.map { String(format: "%.0f%%", $0 * 100) } ?? "—",
            caption: enhancement.hasData
                ? String(localized: "of your words are rewritten by the AI pass")
                : String(localized: "Needs a few more enhanced takes"),
            isPending: !enhancement.hasData,
            action: { onSelect(.enhancement) }
        )
    }

    private var destinationsCard: some View {
        let destinations = insights.destinations
        let top = destinations.destinations.first
        return InsightSummaryCard(
            topic: .destinations,
            value: top.map { InsightFormatting.appName(for: $0.bundleIdentifier) } ?? "—",
            caption: top.map { share in
                let total = max(destinations.totalWords, 1)
                return String(
                    format: String(localized: "%.0f%% of your words land here"),
                    Double(share.words) / Double(total) * 100)
            } ?? String(localized: "Recorded from now on — no history for this"),
            isPending: !destinations.hasData,
            action: { onSelect(.destinations) }
        )
    }

    private var modelsCard: some View {
        let models = insights.models
        let fastest = models.models.compactMap { model -> (String, Double)? in
            model.averageSpeedFactor.map { (model.name, $0) }
        }.max { $0.1 < $1.1 }

        return InsightSummaryCard(
            topic: .models,
            value: fastest.map { String(format: "%.1f×", $0.1) } ?? "—",
            caption: fastest.map {
                String(format: String(localized: "%@ is your fastest, at realtime"), $0.0)
            } ?? String(localized: "Speed and reliability side by side"),
            isPending: !models.hasData,
            action: { onSelect(.models) }
        )
    }
}

enum InsightFormatting {
    /// Bundle identifiers are unreadable, so ask the system for the real name and fall back to the
    /// last path component rather than showing "com.tinyspeck.slackmacgap" to a person.
    static func appName(for bundleIdentifier: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return bundleIdentifier.split(separator: ".").last.map(String.init) ?? bundleIdentifier
    }

    static func appIcon(for bundleIdentifier: String) -> NSImage? {
        guard
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    static func bytes(_ count: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: count)
    }
}
