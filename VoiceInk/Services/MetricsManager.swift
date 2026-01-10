import Foundation
import MetricKit
import OSLog

@available(macOS 12.0, *)
struct MetricsSummary: Codable, Equatable, Sendable {
    let timestampBegin: Date
    let timestampEnd: Date
    let peakMemoryBytes: Double?
    let cumulativeCPUSeconds: Double?
    let avgLaunchTimeSeconds: Double?
    let avgResumeTimeSeconds: Double?
    let cumulativeDiskWritesBytes: Double?
    let hangCount: Int?
    
    var peakMemoryMB: Double? {
        guard let bytes = peakMemoryBytes else { return nil }
        return bytes / 1_048_576
    }
    
    var avgLaunchTimeMs: Double? {
        guard let seconds = avgLaunchTimeSeconds else { return nil }
        return seconds * 1000
    }
    
    var avgResumeTimeMs: Double? {
        guard let seconds = avgResumeTimeSeconds else { return nil }
        return seconds * 1000
    }
    
    var cumulativeDiskWritesKB: Double? {
        guard let bytes = cumulativeDiskWritesBytes else { return nil }
        return bytes / 1024
    }
}

@available(macOS 12.0, *)
@MainActor
final class MetricsManager: NSObject, MXMetricManagerSubscriber {
    static let shared = MetricsManager()
    
    private static let summaryKey = "latestMetricsSummary"
    
    private override init() {
        super.init()
    }
    
    func register() {
        MXMetricManager.shared.add(self)
        AppLogger.metrics.info("MetricsManager registered for metric payloads")
    }
    
    func unregister() {
        MXMetricManager.shared.remove(self)
        AppLogger.metrics.info("MetricsManager unregistered")
    }
    
    // MetricKit invokes delegate methods on arbitrary background queues.
    // These are marked nonisolated and use await to hop to the main actor.
    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        Task { [weak self] in
            for payload in payloads {
                await self?.processMetricPayload(payload)
            }
        }
    }
    
    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        Task { [weak self] in
            for payload in payloads {
                await self?.processDiagnosticPayload(payload)
            }
        }
    }
    
    private func processMetricPayload(_ payload: MXMetricPayload) {
        do {
            AppLogger.metrics.info("Received metric payload for period: \(payload.timeStampBegin) - \(payload.timeStampEnd)")
            
            if let cpuMetrics = payload.cpuMetrics {
                let cpuTime = cpuMetrics.cumulativeCPUTime.value
                AppLogger.metrics.info("CPU - Cumulative time: \(cpuTime, format: .fixed(precision: 2))s")
                
                if let instructionCount = cpuMetrics.cumulativeCPUInstructions {
                    AppLogger.metrics.info("CPU - Instructions: \(instructionCount.value)")
                }
            }
            
            if let memoryMetrics = payload.memoryMetrics {
                let peakMemoryMB = Double(memoryMetrics.peakMemoryUsage.value) / 1_048_576
                AppLogger.metrics.info("Memory - Peak usage: \(peakMemoryMB, format: .fixed(precision: 2)) MB")
                
                let avgSuspendedMB = Double(memoryMetrics.averageSuspendedMemory.averageMeasurement.value) / 1_048_576
                AppLogger.metrics.info("Memory - Avg suspended: \(avgSuspendedMB, format: .fixed(precision: 2)) MB")
            }
            
            if let diskMetrics = payload.diskIOMetrics {
                let writesKB = Double(diskMetrics.cumulativeLogicalWrites.value) / 1024
                AppLogger.metrics.info("Disk - Cumulative writes: \(writesKB, format: .fixed(precision: 2)) KB")
            }
            
            if let launchMetrics = payload.applicationLaunchMetrics {
                if let firstDraw = launchMetrics.histogrammedTimeToFirstDraw.averageMeasurement {
                    let launchTimeMs = firstDraw.value * 1000
                    AppLogger.metrics.info("Launch - Avg time to first draw: \(launchTimeMs, format: .fixed(precision: 2)) ms")
                }
                
                if let resumeTime = launchMetrics.histogrammedApplicationResumeTime.averageMeasurement {
                    let resumeTimeMs = resumeTime.value * 1000
                    AppLogger.metrics.info("Launch - Avg resume time: \(resumeTimeMs, format: .fixed(precision: 2)) ms")
                }
            }
            
            if let responsiveness = payload.applicationResponsivenessMetrics {
                let hangTime = responsiveness.histogrammedApplicationHangTime.averageMeasurement?.value ?? 0
                AppLogger.metrics.info("Responsiveness - Avg hang time: \(hangTime, format: .fixed(precision: 2))s")
            }
            
            try storeLatestMetricsSummary(payload)
        } catch {
            AppLogger.metrics.error("Failed to process metric payload: \(error.localizedDescription)")
        }
    }
    
    private func processDiagnosticPayload(_ payload: MXDiagnosticPayload) {
        AppLogger.metrics.info("Received diagnostic payload for period: \(payload.timeStampBegin) - \(payload.timeStampEnd)")
        
        if let hangDiagnostics = payload.hangDiagnostics {
            AppLogger.metrics.warning("Hang diagnostics count: \(hangDiagnostics.count)")
            for (index, hang) in hangDiagnostics.prefix(5).enumerated() {
                let duration = hang.hangDuration.value
                AppLogger.metrics.warning("Hang \(index + 1): duration \(duration, format: .fixed(precision: 2))s")
            }
        }
        
        if let crashDiagnostics = payload.crashDiagnostics {
            AppLogger.metrics.error("Crash diagnostics count: \(crashDiagnostics.count)")
        }
        
        if let cpuExceptions = payload.cpuExceptionDiagnostics {
            AppLogger.metrics.warning("CPU exception diagnostics count: \(cpuExceptions.count)")
        }
        
        if let diskExceptions = payload.diskWriteExceptionDiagnostics {
            AppLogger.metrics.warning("Disk write exception diagnostics count: \(diskExceptions.count)")
        }
    }
    
    private func storeLatestMetricsSummary(_ payload: MXMetricPayload) throws {
        let hangCount = calculateTotalHangCount(from: payload.applicationResponsivenessMetrics)
        
        let summary = MetricsSummary(
            timestampBegin: payload.timeStampBegin,
            timestampEnd: payload.timeStampEnd,
            peakMemoryBytes: payload.memoryMetrics.map { Double($0.peakMemoryUsage.value) },
            cumulativeCPUSeconds: payload.cpuMetrics?.cumulativeCPUTime.value,
            avgLaunchTimeSeconds: payload.applicationLaunchMetrics?.histogrammedTimeToFirstDraw.averageMeasurement?.value,
            avgResumeTimeSeconds: payload.applicationLaunchMetrics?.histogrammedApplicationResumeTime.averageMeasurement?.value,
            cumulativeDiskWritesBytes: payload.diskIOMetrics.map { Double($0.cumulativeLogicalWrites.value) },
            hangCount: hangCount
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(summary)
        
        UserDefaults.standard.set(data, forKey: Self.summaryKey)
        AppLogger.metrics.debug("Stored metrics summary to UserDefaults")
    }
    
    private func calculateTotalHangCount(from responsiveness: MXAppResponsivenessMetric?) -> Int? {
        guard let histogram = responsiveness?.histogrammedApplicationHangTime else {
            return nil
        }
        
        var totalCount = 0
        let enumerator = histogram.bucketEnumerator
        while let bucket = enumerator.nextObject() as? MXHistogramBucket {
            totalCount += bucket.bucketCount.intValue
        }
        
        return totalCount > 0 ? totalCount : nil
    }
    
    var latestSummary: MetricsSummary? {
        guard let data = UserDefaults.standard.data(forKey: Self.summaryKey) else {
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(MetricsSummary.self, from: data)
        } catch {
            AppLogger.metrics.error("Failed to decode metrics summary: \(error.localizedDescription)")
            return nil
        }
    }
}
