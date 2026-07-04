import SwiftUI
import SwiftData

struct ModelPerformancePanel: View {
    @Binding var selectedPeriod: DashboardInsightPeriod
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .overlay(Divider().opacity(0.5), alignment: .bottom)
                .zIndex(1)

            ZStack(alignment: .bottomTrailing) {
                ModelPerformancePanelContent(filter: selectedPeriod)
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

            InsightPeriodPicker(
                title: "AI model performance period",
                selection: $selectedPeriod
            )

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
    @Query private var metrics: [SessionMetric]

    init(filter: DashboardInsightPeriod) {
        if let predicate = filter.sessionMetricPredicate {
            _metrics = Query(filter: predicate)
        } else {
            _metrics = Query()
        }
    }

    private func makeTranscriptionRows() -> [ModelPerformanceDetailRowData] {
        var accumulators: [String: ModelPerformanceAccumulator] = [:]
        for metric in metrics {
            guard let name = sanitizedModelPerformanceName(metric.transcriptionModelName),
                  let processingDuration = metric.transcriptionDuration,
                  processingDuration > 0 else { continue }
            accumulators[name, default: ModelPerformanceAccumulator()].add(
                audioDuration: metric.audioDuration,
                processingDuration: processingDuration
            )
        }

        return accumulators
            .map { name, accumulator in
                let stat = accumulator.stat(named: name)
                return ModelPerformanceDetailRowData(
                    name: stat.name,
                    kind: .transcription,
                    averageProcessingTime: stat.avgProcessingTime,
                    averageLatencyText: Formatters.formattedPreciseDuration(stat.avgProcessingTime, fallback: "-"),
                    detail: stat.speedFactor > 0 ? String(format: String(localized: "%.1fx realtime"), stat.speedFactor) : nil
                )
            }
            .sortedForPerformanceDetails()
    }

    private func makeEnhancementRows() -> [ModelPerformanceDetailRowData] {
        var accumulators: [String: EnhancementAccumulator] = [:]
        for metric in metrics {
            guard let name = sanitizedModelPerformanceName(metric.aiEnhancementModelName),
                  let processingDuration = metric.enhancementDuration,
                  processingDuration > 0 else { continue }
            accumulators[name, default: EnhancementAccumulator()].add(processingDuration: processingDuration)
        }

        return accumulators
            .map { name, accumulator in
                let stat = accumulator.stat(named: name)
                return ModelPerformanceDetailRowData(
                    name: stat.name,
                    kind: .enhancement,
                    averageProcessingTime: stat.avgProcessingTime,
                    averageLatencyText: Formatters.formattedPreciseDuration(stat.avgProcessingTime, fallback: "-"),
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
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppTheme.Text.secondary)
                    .lineLimit(1)
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
        HStack(alignment: .center, spacing: 12) {
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

private struct ModelPerformanceStat {
    let name: String
    let avgProcessingTime: TimeInterval
    let speedFactor: Double
}

private struct ModelPerformanceAccumulator {
    var sessionCount = 0
    var totalProcessingTime: TimeInterval = 0
    var totalAudioDuration: TimeInterval = 0

    mutating func add(audioDuration: TimeInterval, processingDuration: TimeInterval) {
        sessionCount += 1
        totalProcessingTime += processingDuration
        totalAudioDuration += audioDuration
    }

    func stat(named name: String) -> ModelPerformanceStat {
        let safeCount = max(sessionCount, 1)
        let speedFactor = totalProcessingTime > 0 ? totalAudioDuration / totalProcessingTime : 0
        return ModelPerformanceStat(
            name: name,
            avgProcessingTime: totalProcessingTime / Double(safeCount),
            speedFactor: speedFactor
        )
    }
}

private struct EnhancementStat {
    let name: String
    let avgProcessingTime: TimeInterval
}

private struct EnhancementAccumulator {
    var sessionCount = 0
    var totalProcessingDuration: TimeInterval = 0

    mutating func add(processingDuration: TimeInterval) {
        sessionCount += 1
        totalProcessingDuration += processingDuration
    }

    func stat(named name: String) -> EnhancementStat {
        let safeCount = max(sessionCount, 1)
        return EnhancementStat(
            name: name,
            avgProcessingTime: totalProcessingDuration / Double(safeCount)
        )
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

private func sanitizedModelPerformanceName(_ name: String?) -> String? {
    guard let name else {
        return nil
    }

    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
