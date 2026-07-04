import SwiftUI
import SwiftData

struct ModelUsagePanel: View {
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
                ModelUsagePanelContent(filter: selectedPeriod)
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

            InsightPeriodPicker(
                title: "AI model usage period",
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

private struct ModelUsagePanelContent: View {
    @Query private var metrics: [SessionMetric]

    init(filter: DashboardInsightPeriod) {
        if let predicate = filter.sessionMetricPredicate {
            _metrics = Query(filter: predicate)
        } else {
            _metrics = Query()
        }
    }

    private func makeSummary() -> ModelUsageSummary {
        var transcriptionAudioUsage: [String: TranscriptionAudioAccumulator] = [:]
        var enhancementTokenUsage: [String: EnhancementTokenAccumulator] = [:]

        for metric in metrics {
            if let modelName = sanitizedModelUsageName(metric.transcriptionModelName),
               metric.audioDuration > 0 {
                transcriptionAudioUsage[modelName, default: TranscriptionAudioAccumulator()].add(
                    audioDuration: metric.audioDuration
                )
            }

            if let modelName = sanitizedModelUsageName(metric.aiEnhancementModelName) {
                let tokens = max(metric.enhancementEstimatedTokenCount ?? 0, 0)
                if tokens > 0 {
                    enhancementTokenUsage[modelName, default: EnhancementTokenAccumulator()].add(
                        tokens: tokens
                    )
                }
            }
        }

        return ModelUsageSummary(
            transcriptionModels: transcriptionAudioUsage
                .map { name, accumulator in accumulator.summary(name: name) }
                .sortedForDurationUsage(),
            enhancementModels: enhancementTokenUsage
                .map { name, accumulator in accumulator.summary(name: name) }
                .sortedForTokenUsage()
        )
    }

    var body: some View {
        let summary = makeSummary()

        if summary.hasData {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ModelUsageSection(
                        title: "Transcription Models",
                        valueTitle: "Est. duration",
                        emptyTitle: "No audio duration",
                        emptyIcon: "waveform",
                        rows: summary.transcriptionModels.map { summary in
                            ModelUsageDistributionRowData(
                                name: summary.name,
                                kind: .transcription,
                                value: ModelUsageFormatting.duration(summary.totalAudioDuration)
                            )
                        }
                    )

                    ModelUsageSection(
                        title: "Enhancement Models",
                        valueTitle: "Est. tokens",
                        emptyTitle: "No token estimates",
                        emptyIcon: "number",
                        rows: summary.enhancementModels.map { summary in
                            ModelUsageDistributionRowData(
                                name: summary.name,
                                kind: .enhancement,
                                value: ModelUsageFormatting.tokenCount(summary.estimatedTokens)
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
    let rows: [ModelUsageDistributionRowData]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                VStack(spacing: 10) {
                    ForEach(rows) { row in
                        ModelUsageDistributionRow(row: row)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct ModelUsageDistributionRow: View {
    let row: ModelUsageDistributionRowData

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ModelProviderIcon(modelName: row.name, kind: row.kind, size: 24)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(row.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.Text.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(row.value)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.Text.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(width: 82, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppCardBackground(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.name)
        .accessibilityValue(row.value)
    }
}

private struct ModelUsageDistributionRowData: Identifiable {
    var id: String { name }
    let name: String
    let kind: ModelInsightKind
    let value: String
}

private struct TranscriptionAudioAccumulator {
    var sessionCount = 0
    var totalAudioDuration: TimeInterval = 0

    mutating func add(audioDuration: TimeInterval) {
        sessionCount += 1
        totalAudioDuration += audioDuration
    }

    func summary(name: String) -> TranscriptionModelUsage {
        TranscriptionModelUsage(
            name: name,
            sessionCount: sessionCount,
            totalAudioDuration: totalAudioDuration
        )
    }
}

private struct EnhancementTokenAccumulator {
    var sessionCount = 0
    var totalEstimatedTokens = 0

    mutating func add(tokens: Int) {
        sessionCount += 1
        totalEstimatedTokens += tokens
    }

    func summary(name: String) -> EnhancementTokenUsage {
        EnhancementTokenUsage(
            name: name,
            sessionCount: sessionCount,
            estimatedTokens: totalEstimatedTokens
        )
    }
}

private extension Array where Element == TranscriptionModelUsage {
    func sortedForDurationUsage() -> [TranscriptionModelUsage] {
        sorted { lhs, rhs in
            if lhs.totalAudioDuration != rhs.totalAudioDuration {
                return lhs.totalAudioDuration > rhs.totalAudioDuration
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

private extension Array where Element == EnhancementTokenUsage {
    func sortedForTokenUsage() -> [EnhancementTokenUsage] {
        sorted { lhs, rhs in
            if lhs.estimatedTokens != rhs.estimatedTokens {
                return lhs.estimatedTokens > rhs.estimatedTokens
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

private func sanitizedModelUsageName(_ name: String?) -> String? {
    guard let name else {
        return nil
    }

    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
