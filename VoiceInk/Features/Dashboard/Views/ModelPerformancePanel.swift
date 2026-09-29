import SwiftUI

struct ModelPerformancePanel: View {
    let summaries: [ModelPerformanceSummary]
    let onClose: () -> Void

    var body: some View {
        QuickPanelScaffold {
            ModelPerformancePanelContent(summaries: summaries)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } header: {
            ModelInsightPanelHeader(title: "AI Model Performance", onClose: onClose)
        } footer: {
            RecommendedModelsFooter()
        }
        .background(AppTheme.Insights.page)
    }
}

private struct ModelPerformancePanelContent: View {
    let summaries: [ModelPerformanceSummary]

    private func makeRows(for kind: ModelInsightKind) -> [ModelPerformanceDetailRowData] {
        summaries
            .filter { $0.kind == kind }
            .map { summary in
                ModelPerformanceDetailRowData(
                    name: summary.name,
                    kind: kind,
                    averageProcessingTime: summary.averageProcessingDuration ?? 0,
                    averageLatencyText: Formatters.formattedPreciseDuration(
                        summary.averageProcessingDuration ?? 0, fallback: "-"),
                    detail: kind == .transcription ? summary.averageSpeedFactor.flatMap { speedFactor in
                        speedFactor > 0 ? String(format: String(localized: "%.1fx realtime"), speedFactor) : nil
                    } : nil
                )
            }
            .sortedForPerformanceDetails()
    }

    var body: some View {
        let transcriptionRows = makeRows(for: .transcription)
        let enhancementRows = makeRows(for: .enhancement)

        if transcriptionRows.isEmpty && enhancementRows.isEmpty {
            ModelInsightPanelEmptyState(title: "No model performance for this period")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ModelInsightSection(
                        title: "Transcription Models",
                        valueTitle: "Avg. latency",
                        valueColumnWidth: 96,
                        emptyTitle: "No transcription timings",
                        emptyIcon: "timer",
                        rows: transcriptionRows
                    ) { row, columnWidth in
                        ModelPerformanceDetailRow(row: row, valueColumnWidth: columnWidth)
                    }

                    ModelInsightSection(
                        title: "Enhancement Models",
                        valueTitle: "Avg. latency",
                        valueColumnWidth: 96,
                        emptyTitle: "No enhancement timings",
                        emptyIcon: "sparkles",
                        rows: enhancementRows
                    ) { row, columnWidth in
                        ModelPerformanceDetailRow(row: row, valueColumnWidth: columnWidth)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 76)
                .padding(.bottom, 72)
            }
        }
    }
}

private struct ModelPerformanceDetailRow: View {
    let row: ModelPerformanceDetailRowData
    let valueColumnWidth: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ModelProviderIcon(modelName: row.name, kind: row.kind, size: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.Text.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .truncationMode(.tail)

                if let detail = row.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.Text.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ModelInsightValueText(text: row.averageLatencyText, width: valueColumnWidth)
        }
        .modelInsightRowStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.name)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        if let detail = row.detail {
            return String(localized: "\(row.kind.localizedTitle), \(row.averageLatencyText), \(detail)")
        }

        return String(localized: "\(row.kind.localizedTitle), \(row.averageLatencyText)")
    }
}

private struct ModelPerformanceDetailRowData: Identifiable {
    var id: String { "\(kind.rawValue)-\(name)" }
    let name: String
    let kind: ModelInsightKind
    let averageProcessingTime: TimeInterval
    let averageLatencyText: String
    let detail: String?
}

private extension Array where Element == ModelPerformanceDetailRowData {
    func sortedForPerformanceDetails() -> [ModelPerformanceDetailRowData] {
        sorted { lhs, rhs in
            if lhs.averageProcessingTime != rhs.averageProcessingTime {
                return lhs.averageProcessingTime < rhs.averageProcessingTime
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
