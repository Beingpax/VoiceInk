import SwiftUI

struct ModelPerformanceCard: View {
    let summaries: [ModelPerformanceSummary]
    let onViewMore: () -> Void

    private var transcriptionRows: [ModelPreviewRow] {
        previewRows(for: .transcription)
    }

    private var enhancementRows: [ModelPreviewRow] {
        previewRows(for: .enhancement)
    }

    private func previewRows(for kind: ModelInsightKind) -> [ModelPreviewRow] {
        Array(
            summaries
                .filter { $0.kind == kind }
                .map(Self.previewRow)
                .sortedByUsagePriority()
                .prefix(3)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ModelPreviewCardHeader(
                title: "AI Model Performance",
                viewMoreHelp: String(localized: "Open detailed model performance"),
                onViewMore: onViewMore
            )

            ModelPreviewColumnsRow(
                leftTitle: "Transcription Models",
                leftValueTitle: "Avg. latency",
                leftEmptyTitle: "No transcription models",
                leftEmptyIcon: "timer",
                leftRows: transcriptionRows,
                rightTitle: "Enhancement Models",
                rightValueTitle: "Avg. latency",
                rightEmptyTitle: "No enhancement models",
                rightEmptyIcon: "sparkles",
                rightRows: enhancementRows,
                overallEmptyTitle: "No model performance",
                overallEmptyIcon: "timer",
                valueColumnWidth: 86
            )
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(DashboardInsightCardBackground(cornerRadius: 16))
    }

    private static func previewRow(from summary: ModelPerformanceSummary) -> ModelPreviewRow {
        ModelPreviewRow(
            name: summary.name,
            kind: summary.kind,
            value: Formatters.formattedPreciseDuration(summary.averageProcessingDuration ?? 0, fallback: "-"),
            sessionCount: summary.sessionCount
        )
    }
}
