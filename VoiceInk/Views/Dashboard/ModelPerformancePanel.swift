import SwiftUI
import SwiftData

private func localizedSessionCount(_ count: Int) -> String {
    String(localized: "\(count) sessions")
}

// MARK: - Panel shell (owns filter state)

struct ModelPerformancePanel: View {
    @AppStorage(DashboardProductivityPeriod.modelPerformanceStorageKey) private var filterRaw: String = DashboardProductivityPeriod.lastSevenDays.modelPerformanceStorageValue
    let onClose: () -> Void

    private var filter: DashboardProductivityPeriod {
        DashboardProductivityPeriod(modelPerformanceStorageValue: filterRaw)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .overlay(Divider().opacity(0.5), alignment: .bottom)
                .zIndex(1)

            ModelPerformancePanelContent(filter: filter)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Model Performance")
                .font(.headline.weight(.semibold))
            Spacer()
            Picker(
                "Model performance period",
                selection: Binding(get: { filter }, set: { filterRaw = $0.modelPerformanceStorageValue })
            ) {
                ForEach(DashboardProductivityPeriod.allCases) { f in
                    Text(f.pickerTitle).tag(f)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
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
}

// MARK: - Content (owns @Query, reacts to filter)

private struct ModelPerformancePanelContent: View {
    @Query private var metrics: [SessionMetric]

    init(filter: DashboardProductivityPeriod) {
        if let predicate = filter.sessionMetricPredicate {
            _metrics = Query(filter: predicate)
        } else {
            _metrics = Query()
        }
    }

    private var modelStats: [ModelPerformanceStat] {
        var accumulators: [String: ModelPerformanceAccumulator] = [:]
        for metric in metrics {
            guard let name = metric.transcriptionModelName,
                  let processingDuration = metric.transcriptionDuration,
                  processingDuration > 0 else { continue }
            accumulators[name, default: ModelPerformanceAccumulator()].add(
                audioDuration: metric.audioDuration,
                processingDuration: processingDuration
            )
        }
        return accumulators.map { name, acc in acc.stat(named: name) }
            .sorted { $0.avgProcessingTime < $1.avgProcessingTime }
    }

    private var enhancementStats: [EnhancementStat] {
        var accumulators: [String: EnhancementAccumulator] = [:]
        for metric in metrics {
            guard let name = metric.aiEnhancementModelName,
                  let duration = metric.enhancementDuration,
                  duration > 0 else { continue }
            accumulators[name, default: EnhancementAccumulator()].add(duration: duration)
        }
        return accumulators.map { name, acc in acc.stat(named: name) }
            .sorted { $0.avgDuration < $1.avgDuration }
    }

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        if modelStats.isEmpty && enhancementStats.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !modelStats.isEmpty {
                        modelsSection
                    }
                    if !enhancementStats.isEmpty {
                        enhancementSection
                    }
                }
                .padding(16)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(.secondary)
            Text("No data for this period")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Models grid

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Transcription Models")
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(modelStats) { stat in
                    modelTile(stat)
                }
            }
        }
    }

    private func modelTile(_ stat: ModelPerformanceStat) -> some View {
        VStack(spacing: 10) {
            VStack(spacing: 2) {
                Text(stat.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(localizedSessionCount(stat.sessionCount))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 3) {
                Text(String(format: "%.1fx", stat.speedFactor))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.Data.enhancement)
                Text(stat.speedFactor >= 1.0 ? LocalizedStringKey("Faster than Real-time") : LocalizedStringKey("Slower than Real-time"))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Divider().padding(.horizontal, 8)

            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text(formatDuration(stat.avgAudioDuration))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(AppTheme.Data.transcript)
                    Text("Avg. Audio")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(AppTheme.Border.control)
                    .frame(width: 1, height: 24)

                VStack(spacing: 2) {
                    Text(String(format: "%.2fs", stat.avgProcessingTime))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(AppTheme.Data.audio)
                    Text("Avg. Processing")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(14)
        .background(MetricTintBackground(color: AppTheme.Data.enhancement))
        .cornerRadius(12)
    }

    // MARK: - Enhancement Models

    private var enhancementSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Enhancement Models")
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(enhancementStats) { stat in
                    enhancementTile(stat)
                }
            }
        }
    }

    private func enhancementTile(_ stat: EnhancementStat) -> some View {
        VStack(spacing: 10) {
            VStack(spacing: 2) {
                Text(stat.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(localizedSessionCount(stat.sessionCount))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 3) {
                Text(String(format: "%.2fs", stat.avgDuration))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.Data.transcript)
                Text("Avg. Enhancement Time")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(MetricTintBackground(color: AppTheme.Data.transcript))
        .cornerRadius(12)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? "0s"
    }
}

// MARK: - Data models

struct ModelPerformanceStat: Identifiable {
    var id: String { name }
    let name: String
    let sessionCount: Int
    let totalProcessingTime: TimeInterval
    let avgProcessingTime: TimeInterval
    let avgAudioDuration: TimeInterval
    let speedFactor: Double
}

struct ModelPerformanceAccumulator {
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
            sessionCount: sessionCount,
            totalProcessingTime: totalProcessingTime,
            avgProcessingTime: totalProcessingTime / Double(safeCount),
            avgAudioDuration: totalAudioDuration / Double(safeCount),
            speedFactor: speedFactor
        )
    }
}

struct EnhancementStat: Identifiable {
    var id: String { name }
    let name: String
    let sessionCount: Int
    let avgDuration: TimeInterval
}

struct EnhancementAccumulator {
    var sessionCount = 0
    var totalDuration: TimeInterval = 0

    mutating func add(duration: TimeInterval) {
        sessionCount += 1
        totalDuration += duration
    }

    func stat(named name: String) -> EnhancementStat {
        let safeCount = max(sessionCount, 1)
        return EnhancementStat(
            name: name,
            sessionCount: sessionCount,
            avgDuration: totalDuration / Double(safeCount)
        )
    }
}
