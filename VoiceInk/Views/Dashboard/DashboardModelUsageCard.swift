import SwiftUI

struct DashboardModelUsageCard: View {
    private static let cornerRadius: CGFloat = 16

    let summaries: [DashboardModelUsageSummary]
    let onViewMore: () -> Void

    private var transcriptionSummaries: [DashboardModelUsageSummary] {
        topSummaries(for: .transcription)
    }

    private var enhancementSummaries: [DashboardModelUsageSummary] {
        topSummaries(for: .enhancement)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            HStack(alignment: .top, spacing: 18) {
                DashboardModelPerformanceGroup(
                    modelColumnTitle: "Transcription model",
                    summaries: transcriptionSummaries
                )

                Divider()
                    .opacity(0.45)

                DashboardModelPerformanceGroup(
                    modelColumnTitle: "Enhancement model",
                    summaries: enhancementSummaries
                )
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .topLeading)

            actions
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppCardBackground(cornerRadius: Self.cornerRadius))
    }

    private func openRecommendedModels() {
        if let url = URL(string: "https://tryvoiceink.com/docs/recommended-models") {
            NSWorkspace.shared.open(url)
        }
    }

    private var header: some View {
        Text("AI Model Performance")
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.Text.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.84)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)

            Button(action: openRecommendedModels) {
                DashboardModelActionLabel(
                    title: "Recommended Models",
                    icon: "sparkles",
                    isPrimary: false
                )
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: true)
            .help("Open recommended AI models")

            Button(action: onViewMore) {
                DashboardModelActionLabel(
                    title: "View more",
                    icon: "chart.line.uptrend.xyaxis",
                    isPrimary: true
                )
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: true)
            .help("Open detailed model performance")
        }
    }

    private func topSummaries(for kind: DashboardModelUsageKind) -> [DashboardModelUsageSummary] {
        summaries.filter { $0.kind.rawValue == kind.rawValue }
    }
}

private struct DashboardModelPerformanceGroup: View {
    private static let responseTimeColumnWidth: CGFloat = 92

    let modelColumnTitle: LocalizedStringKey
    let summaries: [DashboardModelUsageSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if summaries.isEmpty {
                tableHeader
                emptyState
            } else {
                VStack(spacing: 0) {
                    tableHeader

                    Divider()
                        .opacity(0.50)

                    ForEach(summaries.indices, id: \.self) { index in
                        DashboardModelPerformanceRow(
                            summary: summaries[index]
                        )

                        if index < summaries.count - 1 {
                            Divider()
                                .opacity(0.35)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    private var tableHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(modelColumnTitle)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.Text.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Response time")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.Text.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(width: Self.responseTimeColumnWidth, alignment: .trailing)
        }
        .padding(.top, 2)
        .padding(.bottom, 5)
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.Text.secondary)

            Text("No sessions")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.Text.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
    }
}

private struct DashboardModelPerformanceRow: View {
    private static let responseTimeColumnWidth: CGFloat = 92

    let summary: DashboardModelUsageSummary

    private var responseTimeText: String {
        Formatters.formattedPreciseDuration(summary.averageDuration ?? 0, fallback: "-")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(summary.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.Text.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(responseTimeText)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.Text.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .frame(width: Self.responseTimeColumnWidth, alignment: .trailing)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summary.name)
        .accessibilityValue("\(responseTimeText) response time")
    }
}

private struct DashboardModelActionLabel: View {
    let title: LocalizedStringKey
    let icon: String
    let isPrimary: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))

            Text(title)
                .lineLimit(1)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(isPrimary ? Color.white : AppTheme.Text.primary)
        .padding(.horizontal, isPrimary ? 14 : 12)
        .frame(height: 34)
        .background(isPrimary ? AppTheme.Accent.primary : AppTheme.Surface.subtle)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isPrimary ? AppTheme.Accent.border.opacity(0.45) : AppTheme.Border.subtle.opacity(0.65), lineWidth: 1)
        )
        .shadow(color: Color.clear, radius: 0)
    }
}
