import SwiftUI

enum ModelUsageText {
    static let estimateInfo: LocalizedStringKey =
        "These estimated tokens are a rough estimate of token usage. They are not exact token counts or provider-reported billing usage."
}

struct ModelUsageCard: View {
    let summary: ModelUsageSummary
    let onViewMore: () -> Void

    private var transcriptionRows: [ModelPreviewRow] {
        Array(
            summary.transcriptionModels
                .map { item in
                    ModelPreviewRow(
                        name: item.name,
                        kind: .transcription,
                        value: ModelUsageFormatting.duration(item.totalAudioDuration),
                        sessionCount: item.sessionCount
                    )
                }
                .prefix(3)
        )
    }

    private var enhancementRows: [ModelPreviewRow] {
        Array(
            summary.enhancementModels
                .map { item in
                    ModelPreviewRow(
                        name: item.name,
                        kind: .enhancement,
                        value: ModelUsageFormatting.tokenCount(item.estimatedTokens),
                        sessionCount: item.sessionCount
                    )
                }
                .prefix(3)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ModelPreviewCardHeader(
                title: "AI Model Usage",
                infoTip: ModelUsageText.estimateInfo,
                viewMoreHelp: String(localized: "Open detailed AI model usage"),
                onViewMore: onViewMore
            )

            ModelPreviewColumnsRow(
                leftTitle: "Transcription Models",
                leftValueTitle: "Est. duration",
                leftEmptyTitle: "No transcription models",
                leftEmptyIcon: "waveform",
                leftRows: transcriptionRows,
                rightTitle: "Enhancement Models",
                rightValueTitle: "Est. tokens",
                rightEmptyTitle: "No enhancement models",
                rightEmptyIcon: "number",
                rightRows: enhancementRows,
                overallEmptyTitle: "No model usage",
                overallEmptyIcon: "chart.bar.doc.horizontal",
                valueColumnWidth: 74
            )
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(DashboardInsightCardBackground(cornerRadius: 16))
    }
}

enum ModelUsageFormatting {
    static func duration(_ interval: TimeInterval) -> String {
        if interval < 3600 {
            return Formatters.formattedDuration(interval, style: .abbreviated, fallback: "0m")
        }

        return Formatters.formattedCompactHoursAndMinutes(interval)
    }

    static func tokenCount(_ count: Int) -> String {
        Formatters.formattedCompactNumber(max(0, count))
    }
}
