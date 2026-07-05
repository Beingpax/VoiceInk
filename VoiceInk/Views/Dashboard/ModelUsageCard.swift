import SwiftUI

enum ModelUsageText {
    static let estimateInfo: LocalizedStringKey = "These estimated tokens are a rough estimate of token usage. They are not exact token counts or provider-reported billing usage."
}

struct ModelUsageCard: View {
    let summary: ModelUsageSummary
    let onViewMore: () -> Void

    private var transcriptionRows: [ModelUsagePreviewRow] {
        Array(
            summary.transcriptionModels
                .map { item in
                    ModelUsagePreviewRow(
                        name: item.name,
                        kind: .transcription,
                        value: ModelUsageFormatting.duration(item.totalAudioDuration)
                    )
                }
                .prefix(3)
        )
    }

    private var enhancementRows: [ModelUsagePreviewRow] {
        Array(
            summary.enhancementModels
                .map { item in
                    ModelUsagePreviewRow(
                        name: item.name,
                        kind: .enhancement,
                        value: ModelUsageFormatting.tokenCount(item.estimatedTokens)
                    )
                }
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
        HStack(alignment: .center, spacing: 6) {
            Text("AI Model Usage")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Text.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.84)

            InfoTip(ModelUsageText.estimateInfo)
                .help(Text(ModelUsageText.estimateInfo))

            Spacer(minLength: 0)

            Button(action: onViewMore) {
                ModelDetailActionLabel(title: "View details")
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: true)
            .help(String(localized: "Open detailed AI model usage"))
        }
    }

    @ViewBuilder
    private var previewColumns: some View {
        if transcriptionRows.isEmpty && enhancementRows.isEmpty {
            InsightEmptyState(title: "No model usage", icon: "chart.bar.doc.horizontal")
        } else {
            HStack(alignment: .top, spacing: 18) {
                ModelUsagePreviewColumn(
                    title: "Transcription Models",
                    valueTitle: "Est. duration",
                    emptyTitle: "No transcription models",
                    emptyIcon: "waveform",
                    rows: transcriptionRows
                )

                Divider()
                    .opacity(0.45)

                ModelUsagePreviewColumn(
                    title: "Enhancement Models",
                    valueTitle: "Est. tokens",
                    emptyTitle: "No enhancement models",
                    emptyIcon: "number",
                    rows: enhancementRows
                )
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ModelUsagePreviewColumn: View {
    let title: LocalizedStringKey
    let valueTitle: LocalizedStringKey
    let emptyTitle: LocalizedStringKey
    let emptyIcon: String
    let rows: [ModelUsagePreviewRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(valueTitle)
                    .frame(width: 74, alignment: .trailing)
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
                        ModelUsagePreviewRowView(row: row)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct ModelUsagePreviewRowView: View {
    let row: ModelUsagePreviewRow

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

            Text(row.value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.Text.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .frame(width: 74, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(AppCardBackground(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.name)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        String(localized: "\(row.kindTitle), \(row.value)")
    }
}

private struct ModelUsagePreviewRow: Identifiable {
    var id: String { "\(kind.rawValue)-\(name)" }
    let name: String
    let kind: ModelInsightKind
    let value: String

    var kindTitle: String {
        kind == .transcription ? String(localized: "Transcription") : String(localized: "Enhancement")
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
