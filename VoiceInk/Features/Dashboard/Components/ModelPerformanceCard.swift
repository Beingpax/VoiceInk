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
        summaries
            .filter { $0.kind == kind }
            .sortedForPerformanceDisplay()
            .prefix(3)
            .map(Self.previewRow)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
        .dashboardInsightCardStyle(padding: 20, alignment: .topLeading)
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
