import SwiftUI

struct ModelUsagePanel: View {
    let summary: ModelUsageSummary
    let onClose: () -> Void

    var body: some View {
        QuickPanelScaffold {
            ModelUsagePanelContent(summary: summary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } header: {
            ModelInsightPanelHeader(title: "AI Model Usage", onClose: onClose)
        } footer: {
            RecommendedModelsFooter()
        }
        .background(AppTheme.Insights.page)
    }
}

private struct ModelUsagePanelContent: View {
    let summary: ModelUsageSummary

    var body: some View {
        if summary.hasData {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ModelUsageSection(
                        title: "Transcription Models",
                        valueTitle: "Est. duration",
                        emptyTitle: "No audio duration",
                        emptyIcon: "waveform",
                        tint: AppTheme.Insights.productivity,
                        rows: summary.transcriptionModels.map { summary in
                            ModelUsageDistributionRowData(
                                name: summary.name,
                                kind: .transcription,
                                value: ModelUsageFormatting.duration(summary.totalAudioDuration),
                                amount: summary.totalAudioDuration
                            )
                        }
                    )

                    ModelUsageSection(
                        title: "Enhancement Models",
                        valueTitle: "Est. tokens",
                        emptyTitle: "No token estimates",
                        emptyIcon: "number",
                        tint: AppTheme.Insights.activity,
                        rows: summary.enhancementModels.map { summary in
                            ModelUsageDistributionRowData(
                                name: summary.name,
                                kind: .enhancement,
                                value: ModelUsageFormatting.tokenCount(summary.estimatedTokens),
                                amount: Double(summary.estimatedTokens)
                            )
                        }
                    )
                }
                .padding(.horizontal, 18)
                .padding(.top, 76)
                .padding(.bottom, 72)
            }
        } else {
            ModelInsightPanelEmptyState(title: "No model usage for this period")
        }
    }
}

private struct ModelUsageSection: View {
    let title: LocalizedStringKey
    let valueTitle: LocalizedStringKey
    let emptyTitle: LocalizedStringKey
    let emptyIcon: String
    let tint: Color
    let rows: [ModelUsageDistributionRowData]

    var body: some View {
        let totalAmount = rows.reduce(0) { $0 + $1.amount }

        ModelInsightSection(
            title: title,
            valueTitle: valueTitle,
            valueColumnWidth: 74,
            emptyTitle: emptyTitle,
            emptyIcon: emptyIcon,
            rows: rows
        ) { row, columnWidth in
            ModelUsageDistributionRow(
                row: row,
                share: totalAmount > 0 ? row.amount / totalAmount : 0,
                tint: tint,
                valueColumnWidth: columnWidth
            )
        }
    }
}

private struct ModelUsageDistributionRow: View {
    let row: ModelUsageDistributionRowData
    let share: Double
    let tint: Color
    let valueColumnWidth: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ModelProviderIcon(modelName: row.name, kind: row.kind, size: 24)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.Text.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(share, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Text.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(width: 34, alignment: .trailing)
                        .layoutPriority(1)
                }

                ModelUsageShareBar(share: share, tint: tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ModelInsightValueText(text: row.value, width: valueColumnWidth)
        }
        .modelInsightRowStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.name)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        String(localized: "\(row.kind.localizedTitle), \(row.value), \(share.formatted(.percent.precision(.fractionLength(0))))")
    }
}

private struct ModelUsageDistributionRowData: Identifiable {
    var id: String { name }
    let name: String
    let kind: ModelInsightKind
    let value: String
    let amount: Double
}

private struct ModelUsageShareBar: View {
    let share: Double
    let tint: Color

    private var normalizedShare: Double {
        min(max(share, 0), 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let filledWidth = geometry.size.width * CGFloat(normalizedShare)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(tint.opacity(0.12))

                if normalizedShare > 0 {
                    Capsule()
                        .fill(tint)
                        .frame(width: min(geometry.size.width, max(4, filledWidth)))
                }
            }
        }
        .frame(height: 5)
    }
}
