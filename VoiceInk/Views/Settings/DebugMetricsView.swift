#if DEBUG
import SwiftUI

@available(macOS 12.0, *)
struct DebugMetricsView: View {
    @State private var summary: MetricsSummary?
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
    
    var body: some View {
        GroupBox("MetricKit Summary") {
            if let summary = summary {
                VStack(alignment: .leading, spacing: 8) {
                    if let peakMB = summary.peakMemoryMB {
                        MetricRow(label: "Peak Memory", value: String(format: "%.2f MB", peakMB))
                    }
                    
                    if let cpuTime = summary.cumulativeCPUSeconds {
                        MetricRow(label: "CPU Time", value: String(format: "%.2f s", cpuTime))
                    }
                    
                    if let launchMs = summary.avgLaunchTimeMs {
                        MetricRow(label: "Avg Launch Time", value: String(format: "%.2f ms", launchMs))
                    }
                    
                    if let resumeMs = summary.avgResumeTimeMs {
                        MetricRow(label: "Avg Resume Time", value: String(format: "%.2f ms", resumeMs))
                    }
                    
                    if let diskKB = summary.cumulativeDiskWritesKB {
                        MetricRow(label: "Disk Writes", value: String(format: "%.2f KB", diskKB))
                    }
                    
                    if let hangCount = summary.hangCount, hangCount > 0 {
                        MetricRow(label: "Hang Events", value: "\(hangCount)")
                    }
                    
                    Divider()
                    
                    MetricRow(
                        label: "Period",
                        value: "\(Self.dateFormatter.string(from: summary.timestampBegin)) - \(Self.dateFormatter.string(from: summary.timestampEnd))"
                    )
                }
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No metrics received yet")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text("Metrics are collected daily by MetricKit")
                        .foregroundStyle(.tertiary)
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
        .onAppear {
            loadSummary()
        }
    }
    
    private func loadSummary() {
        summary = MetricsManager.shared.latestSummary
    }
}

@available(macOS 12.0, *)
private struct MetricRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .font(.caption)
    }
}

@available(macOS 12.0, *)
#Preview {
    DebugMetricsView()
        .padding()
        .frame(width: 300)
}
#endif
