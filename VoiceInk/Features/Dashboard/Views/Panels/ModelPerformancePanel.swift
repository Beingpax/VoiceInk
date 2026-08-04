import SwiftUI

struct ModelPerformancePanel: View {
    let summaries: [ModelPerformanceSummary]
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .overlay(Divider().opacity(0.5), alignment: .bottom)
                .zIndex(1)

            ZStack(alignment: .bottomTrailing) {
                ModelPerformancePanelContent(summaries: summaries)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                recommendedModelsOverlay
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("AI Model Performance")
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

private struct ModelPerformancePanelContent: View {
    let summaries: [ModelPerformanceSummary]

    private func makeTranscriptionRows() -> [ModelPerformanceDetailRowData] {
        summaries
            .filter { $0.kind == .transcription }
            .map { summary in
                return ModelPerformanceDetailRowData(
                    name: summary.name,
                    kind: .transcription,
                    averageProcessingTime: summary.averageProcessingDuration ?? 0,
                    averageLatencyText: Formatters.formattedPreciseDuration(
                        summary.averageProcessingDuration ?? 0, fallback: "-"),
                    detail: summary.averageSpeedFactor.flatMap { speedFactor in
                        speedFactor > 0 ? String(format: String(localized: "%.1fx realtime"), speedFactor) : nil
                    }
                )
            }
            .sortedForPerformanceDetails()
    }

    private func makeEnhancementRows() -> [ModelPerformanceDetailRowData] {
        summaries
            .filter { $0.kind == .enhancement }
            .map { summary in
                return ModelPerformanceDetailRowData(
                    name: summary.name,
                    kind: .enhancement,
                    averageProcessingTime: summary.averageProcessingDuration ?? 0,
                    averageLatencyText: Formatters.formattedPreciseDuration(
                        summary.averageProcessingDuration ?? 0, fallback: "-"),
                    detail: nil
                )
            }
            .sortedForPerformanceDetails()
    }

    var body: some View {
        let transcriptionRows = makeTranscriptionRows()
        let enhancementRows = makeEnhancementRows()

        if transcriptionRows.isEmpty && enhancementRows.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ModelPerformanceDetailSection(
                        title: "Transcription Models",
                        valueTitle: "Avg. latency",
                        emptyTitle: "No transcription timings",
                        emptyIcon: "timer",
                        rows: transcriptionRows
                    )

                    ModelPerformanceDetailSection(
                        title: "Enhancement Models",
                        valueTitle: "Avg. latency",
                        emptyTitle: "No enhancement timings",
                        emptyIcon: "sparkles",
                        rows: enhancementRows
                    )
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 86)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(.secondary)

            Text("No model performance for this period")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ModelPerformanceDetailSection: View {
    let title: LocalizedStringKey
    let valueTitle: LocalizedStringKey
    let emptyTitle: LocalizedStringKey
    let emptyIcon: String
    let rows: [ModelPerformanceDetailRowData]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(valueTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.Text.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(width: 96, alignment: .trailing)
                    .padding(.trailing, 4)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppTheme.Text.primary)
            .lineLimit(1)

            if rows.isEmpty {
                InsightEmptyState(title: emptyTitle, icon: emptyIcon)
            } else {
                VStack(spacing: 8) {
                    ForEach(rows) { row in
                        ModelPerformanceDetailRow(row: row)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct ModelPerformanceDetailRow: View {
    let row: ModelPerformanceDetailRowData

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ModelProviderIcon(modelName: row.name, kind: row.kind, size: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.Text.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .truncationMode(.tail)

                if let detail = row.detail {
                    HStack(spacing: 6) {
                        Text(detail)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(AppTheme.Text.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.averageLatencyText)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.Text.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: 96, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppCardBackground(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.name)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        if let detail = row.detail {
            return String(localized: "\(row.kindTitle), \(row.averageLatencyText), \(detail)")
        }

        return String(localized: "\(row.kindTitle), \(row.averageLatencyText)")
    }
}

private struct ModelPerformanceDetailRowData: Identifiable {
    var id: String { "\(kind.rawValue)-\(name)" }
    let name: String
    let kind: ModelInsightKind
    let averageProcessingTime: TimeInterval
    let averageLatencyText: String
    let detail: String?

    var kindTitle: String {
        kind == .transcription ? String(localized: "Transcription") : String(localized: "Enhancement")
    }
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
