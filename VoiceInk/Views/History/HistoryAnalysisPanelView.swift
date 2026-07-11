import SwiftUI

struct HistoryAnalysisPanelView: View {
    let transcriptions: [Transcription]
    let onClose: () -> Void

    private let analysis: HistoryPerformanceAnalysis

    init(transcriptions: [Transcription], onClose: @escaping () -> Void) {
        self.transcriptions = transcriptions
        self.onClose = onClose
        self.analysis = HistoryPerformanceAnalysis(transcriptions: transcriptions)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .overlay(Divider().opacity(0.5), alignment: .bottom)
                .zIndex(1)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Performance Analysis")
                    .font(.headline.weight(.semibold))

                Text(String(localized: "\(analysis.totalTranscripts) selected transcripts"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.Text.secondary)
            }

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

    @ViewBuilder
    private var content: some View {
        if analysis.transcriptionRows.isEmpty && analysis.enhancementRows.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HistoryPerformanceSection(
                        title: "Transcription Models",
                        valueTitle: "Avg. latency",
                        emptyTitle: "No transcription timings",
                        emptyIcon: "timer",
                        rows: analysis.transcriptionRows
                    )

                    HistoryPerformanceSection(
                        title: "Enhancement Models",
                        valueTitle: "Avg. latency",
                        emptyTitle: "No enhancement timings",
                        emptyIcon: "sparkles",
                        rows: analysis.enhancementRows
                    )
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(AppTheme.Text.secondary)

            Text("No model performance in selection")
                .font(.subheadline)
                .foregroundStyle(AppTheme.Text.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HistoryPerformanceAnalysis {
    let totalTranscripts: Int
    let transcriptionRows: [HistoryPerformanceRowData]
    let enhancementRows: [HistoryPerformanceRowData]

    init(transcriptions: [Transcription]) {
        var transcriptionStats: [String: HistoryPerformanceAccumulator] = [:]
        var enhancementStats: [String: HistoryPerformanceAccumulator] = [:]

        for transcription in transcriptions {
            if let modelName = Self.modelName(transcription.transcriptionModelName),
                let duration = transcription.transcriptionDuration,
                duration > 0
            {
                transcriptionStats[modelName, default: HistoryPerformanceAccumulator()].add(
                    processingDuration: duration,
                    audioDuration: transcription.duration
                )
            }

            if let modelName = Self.modelName(transcription.aiEnhancementModelName),
                let duration = transcription.enhancementDuration,
                duration > 0
            {
                enhancementStats[modelName, default: HistoryPerformanceAccumulator()].add(
                    processingDuration: duration
                )
            }
        }

        self.totalTranscripts = transcriptions.count
        self.transcriptionRows = transcriptionStats.map { modelName, stats in
            stats.row(kind: .transcription, name: modelName)
        }
        .sortedForHistoryPerformance()
        self.enhancementRows = enhancementStats.map { modelName, stats in
            stats.row(kind: .enhancement, name: modelName)
        }
        .sortedForHistoryPerformance()
    }

    private static func modelName(_ name: String?) -> String? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct HistoryPerformanceAccumulator {
    var sessionCount = 0
    var totalProcessingDuration: TimeInterval = 0
    var totalAudioDuration: TimeInterval = 0

    mutating func add(processingDuration: TimeInterval, audioDuration: TimeInterval = 0) {
        sessionCount += 1
        totalProcessingDuration += processingDuration
        totalAudioDuration += max(audioDuration, 0)
    }

    func row(kind: HistoryPerformanceKind, name: String) -> HistoryPerformanceRowData {
        let averageProcessingDuration = sessionCount > 0 ? totalProcessingDuration / Double(sessionCount) : 0
        let speedFactor =
            totalProcessingDuration > 0 && totalAudioDuration > 0 ? totalAudioDuration / totalProcessingDuration : nil

        return HistoryPerformanceRowData(
            name: name,
            kind: kind,
            averageProcessingDuration: averageProcessingDuration,
            averageLatencyText: Formatters.formattedPreciseDuration(averageProcessingDuration),
            detail: speedFactor.map { String(format: String(localized: "%.1fx realtime"), $0) }
        )
    }
}

private enum HistoryPerformanceKind: String {
    case transcription
    case enhancement

    var modelInsightKind: ModelInsightKind {
        switch self {
        case .transcription:
            return .transcription
        case .enhancement:
            return .enhancement
        }
    }

    var kindTitle: String {
        modelInsightKind == .transcription ? String(localized: "Transcription") : String(localized: "Enhancement")
    }
}

private struct HistoryPerformanceRowData: Identifiable {
    var id: String { "\(kind.rawValue)-\(name)" }
    let name: String
    let kind: HistoryPerformanceKind
    let averageProcessingDuration: TimeInterval
    let averageLatencyText: String
    let detail: String?
}

private extension Array where Element == HistoryPerformanceRowData {
    func sortedForHistoryPerformance() -> [HistoryPerformanceRowData] {
        sorted { lhs, rhs in
            if lhs.averageProcessingDuration != rhs.averageProcessingDuration {
                return lhs.averageProcessingDuration < rhs.averageProcessingDuration
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

private struct HistoryPerformanceSection: View {
    let title: LocalizedStringKey
    let valueTitle: LocalizedStringKey
    let emptyTitle: LocalizedStringKey
    let emptyIcon: String
    let rows: [HistoryPerformanceRowData]

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
                HistoryPerformanceEmptyRow(title: emptyTitle, icon: emptyIcon)
            } else {
                VStack(spacing: 8) {
                    ForEach(rows) { row in
                        HistoryPerformanceRow(row: row)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct HistoryPerformanceRow: View {
    let row: HistoryPerformanceRowData

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ModelProviderIcon(modelName: row.name, kind: row.kind.modelInsightKind, size: 24)

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
            return String(localized: "\(row.kind.kindTitle), \(row.averageLatencyText), \(detail)")
        }

        return String(localized: "\(row.kind.kindTitle), \(row.averageLatencyText)")
    }
}

private struct HistoryPerformanceEmptyRow: View {
    let title: LocalizedStringKey
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.Text.secondary)

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.Text.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
    }
}
