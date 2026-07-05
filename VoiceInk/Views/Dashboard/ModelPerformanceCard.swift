import SwiftUI

struct ModelPerformanceCard: View {
    let summaries: [ModelPerformanceSummary]
    let onViewMore: () -> Void

    private var transcriptionRows: [ModelPerformancePreviewRow] {
        Array(
            summaries
                .filter { $0.kind == .transcription }
                .map(ModelPerformancePreviewRow.init(summary:))
                .sortedForPerformancePreview()
                .prefix(3)
        )
    }

    private var enhancementRows: [ModelPerformancePreviewRow] {
        Array(
            summaries
                .filter { $0.kind == .enhancement }
                .map(ModelPerformancePreviewRow.init(summary:))
                .sortedForPerformancePreview()
                .prefix(3)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            previewColumns
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(DashboardInsightCardBackground(cornerRadius: 16))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("AI Model Performance")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Text.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.84)

            Spacer(minLength: 0)

            Button(action: onViewMore) {
                ModelDetailActionLabel(title: "View details")
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: true)
            .help(String(localized: "Open detailed model performance"))
        }
    }

    @ViewBuilder
    private var previewColumns: some View {
        if transcriptionRows.isEmpty && enhancementRows.isEmpty {
            InsightEmptyState(title: "No model performance", icon: "timer")
        } else {
            HStack(alignment: .top, spacing: 18) {
                ModelPerformancePreviewColumn(
                    title: "Transcription Models",
                    valueTitle: "Avg. latency",
                    emptyTitle: "No transcription models",
                    emptyIcon: "timer",
                    rows: transcriptionRows
                )

                Divider()
                    .opacity(0.45)

                ModelPerformancePreviewColumn(
                    title: "Enhancement Models",
                    valueTitle: "Avg. latency",
                    emptyTitle: "No enhancement models",
                    emptyIcon: "sparkles",
                    rows: enhancementRows
                )
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ModelPerformancePreviewColumn: View {
    let title: LocalizedStringKey
    let valueTitle: LocalizedStringKey
    let emptyTitle: LocalizedStringKey
    let emptyIcon: String
    let rows: [ModelPerformancePreviewRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(valueTitle)
                    .frame(width: 86, alignment: .trailing)
                    .padding(.trailing, 4)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AppTheme.Text.secondary)
            .lineLimit(1)

            if rows.isEmpty {
                InsightEmptyState(title: emptyTitle, icon: emptyIcon)
            } else {
                VStack(spacing: 8) {
                    ForEach(rows) { row in
                        ModelPerformancePreviewRowView(row: row)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct ModelPerformancePreviewRowView: View {
    let row: ModelPerformancePreviewRow

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ModelProviderIcon(modelName: row.name, kind: row.kind, size: 22)

            Text(row.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.Text.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.averageLatencyText)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.Text.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .frame(width: 86, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(AppCardBackground(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.name)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        String(localized: "\(row.kindTitle), \(row.averageLatencyText) average latency")
    }
}

private struct ModelPerformancePreviewRow: Identifiable {
    var id: String { "\(kind.rawValue)-\(name)" }
    let name: String
    let kind: ModelInsightKind
    let averageLatencyText: String
    let sessionCount: Int

    var kindTitle: String {
        kind == .transcription ? String(localized: "Transcription") : String(localized: "Enhancement")
    }

    init(summary: ModelPerformanceSummary) {
        self.name = summary.name
        self.kind = summary.kind
        self.averageLatencyText = Formatters.formattedPreciseDuration(summary.averageProcessingDuration ?? 0, fallback: "-")
        self.sessionCount = summary.sessionCount
    }
}

private extension Array where Element == ModelPerformancePreviewRow {
    func sortedForPerformancePreview() -> [ModelPerformancePreviewRow] {
        sorted { lhs, rhs in
            if lhs.sessionCount != rhs.sessionCount {
                return lhs.sessionCount > rhs.sessionCount
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
