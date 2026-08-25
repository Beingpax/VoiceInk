import Foundation
import OSLog

final class LogExporter {
    static let shared = LogExporter()

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "LogExporter")
    private let subsystem = "com.prakashjoshipax.voiceink"
    private let exportWindow: TimeInterval = 30 * 60

    private init() {
        logger.notice("🎙️ LogExporter initialized with a 30-minute export window")
    }

    func exportLogs() async throws -> URL {
        logger.notice("🎙️ Starting log export")

        let logs = try await fetchLogs()
        let fileURL = try saveLogsToFile(logs)

        logger.notice("🎙️ Log export completed: \(fileURL.path, privacy: .public)")
        return fileURL
    }

    private func fetchLogs() async throws -> [String] {
        let diagnosticContext = await MainActor.run {
            ShortcutDiagnostics.logHealthReport(reason: "log-export-requested")
            return (
                systemInfo: SystemInfoService.shared.getSystemInfoString(),
                shortcutHealth: ShortcutDiagnostics.healthReport(),
                shortcutEnvironment: ShortcutDiagnostics.environmentSnapshot().summary
            )
        }

        let rangeEnd = Date()
        let rangeStart = rangeEnd.addingTimeInterval(-exportWindow)

        let store = try OSLogStore(scope: .system)
        let predicate = NSPredicate(format: "subsystem == %@", subsystem)

        var logLines: [String] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        logLines.append("=== VoiceInk Diagnostic Logs ===")
        logLines.append("Export Date: \(dateFormatter.string(from: rangeEnd))")
        logLines.append("Subsystem: \(subsystem)")
        logLines.append("Log Range Start: \(dateFormatter.string(from: rangeStart))")
        logLines.append("Log Range End: \(dateFormatter.string(from: rangeEnd))")
        logLines.append("Log Window: Most recent 30 minutes")
        logLines.append("================================")
        logLines.append("")
        logLines.append(diagnosticContext.systemInfo)
        logLines.append("")
        logLines.append("=== SHORTCUT RUNTIME HEALTH AT EXPORT ===")
        logLines.append(diagnosticContext.shortcutHealth)
        logLines.append("Environment: \(diagnosticContext.shortcutEnvironment)")
        logLines.append("=== END SHORTCUT RUNTIME HEALTH ===")
        logLines.append("")
        logLines.append("--- Unified Logs (Most Recent 30 Minutes) ---")
        logLines.append("")

        let position = store.position(date: rangeStart)
        let entries = try store.getEntries(at: position, matching: predicate)

        var exportedLogCount = 0
        for entry in entries {
            guard let logEntry = entry as? OSLogEntryLog else { continue }
            guard logEntry.date >= rangeStart else { continue }
            if logEntry.date > rangeEnd { break }

            let timestamp = dateFormatter.string(from: logEntry.date)
            let level = logLevelString(logEntry.level)
            let category = logEntry.category
            let message = logEntry.composedMessage

            logLines.append("[\(timestamp)] [\(level)] [\(category)] \(message)")
            exportedLogCount += 1
        }

        if exportedLogCount == 0 {
            logLines.append("No VoiceInk unified logs found in the most recent 30 minutes.")
        }
        logLines.append("")
        logLines.append("Exported Unified Log Entries: \(exportedLogCount)")

        return logLines
    }

    private func logLevelString(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .undefined: return "UNDEFINED"
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTICE"
        case .error: return "ERROR"
        case .fault: return "FAULT"
        @unknown default: return "UNKNOWN"
        }
    }

    private func saveLogsToFile(_ logs: [String]) throws -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let fileName = "VoiceInk_Logs_\(timestamp).log"

        guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            throw NSError(
                domain: "LogExporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Downloads directory unavailable"]
            )
        }

        let fileURL = downloadsURL.appendingPathComponent(fileName)
        let content = logs.joined(separator: "\n")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        return fileURL
    }
}
