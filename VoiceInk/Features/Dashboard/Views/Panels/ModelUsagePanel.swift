import SwiftUI

struct ModelUsagePanel: View {
    let summary: ModelUsageSummary
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .overlay(Divider().opacity(0.5), alignment: .bottom)
                .zIndex(1)

            ZStack(alignment: .bottomTrailing) {
                ModelUsagePanelContent(summary: summary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                recommendedModelsOverlay
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("AI Model Usage")
                .font(.headline.weight(.semibold))

            Spacer()

            AppIconButton(
                systemName: "xmark",
                help: "Close",
                size: 28,
                iconSize: 14,
                cornerRadius: AppTheme.Radius.control,
                action: onClose
            )
        }
    }

    private var recommendedModelsOverlay: some View {
        Button(action: ModelLinks.openRecommendedModels) {
            ModelActionLabel(
                title: "Recommended Models",
                icon: "sparkles",
                isPrimary: true
            )
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: true)
        .help(String(localized: "Open recommended AI models"))
        .padding(.trailing, 20)
        .padding(.bottom, 16)
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
                        tint: AppTheme.Status.infoStrong,
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
                        tint: AppTheme.Status.positive,
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
                .padding(.top, 18)
                .padding(.bottom, 86)
            }
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(.secondary)

            Text("No model usage for this period")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ModelUsageSection: View {
    let title: LocalizedStringKey
    let valueTitle: LocalizedStringKey
    let emptyTitle: LocalizedStringKey
    let emptyIcon: String
    let tint: Color
    let rows: [ModelUsageDistributionRowData]

    private var totalAmount: Double {
        rows.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(valueTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.Text.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(width: 74, alignment: .trailing)
                    .padding(.trailing, 4)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppTheme.Text.primary)
            .lineLimit(1)

            if rows.isEmpty {
                InsightEmptyState(title: emptyTitle, icon: emptyIcon)
            } else {
                VStack(spacing: 10) {
                    ForEach(rows) { row in
                        ModelUsageDistributionRow(
                            row: row,
                            share: share(for: row),
                            tint: tint
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func share(for row: ModelUsageDistributionRowData) -> Double {
        guard totalAmount > 0 else {
            return 0
        }

        return row.amount / totalAmount
    }
}

private struct ModelUsageDistributionRow: View {
    let row: ModelUsageDistributionRowData
    let share: Double
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ModelProviderIcon(modelName: row.name, kind: row.kind, size: 24)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.Text.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(share, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Text.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(width: 34, alignment: .trailing)
                        .layoutPriority(1)
                }

                ModelUsageShareBar(share: share, tint: tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.Text.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: 58, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppCardBackground(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.name)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        String(localized: "\(row.kindTitle), \(row.value), \(share.formatted(.percent.precision(.fractionLength(0))))")
    }
}

private struct ModelUsageDistributionRowData: Identifiable {
    var id: String { name }
    let name: String
    let kind: ModelInsightKind
    let value: String
    let amount: Double

    var kindTitle: String {
        kind == .transcription ? String(localized: "Transcription") : String(localized: "Enhancement")
    }
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
                    .fill(AppTheme.Surface.subtle)

                if normalizedShare > 0 {
                    Capsule()
                        .fill(tint.opacity(0.82))
                        .frame(width: max(6, filledWidth))
                }
            }
        }
        .frame(height: 5)
    }
}
