import Foundation
import OSLog

final class LogExporter {
    static let shared = LogExporter()

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "LogExporter")
    private let subsystem = "com.prakashjoshipax.voiceink"

    /// OSLogStore is disk-backed and keyed by wall-clock time, not process lifetime, so a plain
    /// time window (rather than tracking app session boundaries) still spans an app restart —
    /// e.g. a shortcut that breaks and is only "fixed" by restarting still has its pre-restart
    /// logs included as long as the restart happened within this window.
    private let exportWindow: TimeInterval = 60 * 60

    private init() {}

    func exportLogs() async throws -> URL {
        logger.notice("🎙️ Starting log export")

        // Force a fresh shortcut health probe so the export always contains
        // current permission/tap/config state even if the user never hit a key.
        await MainActor.run {
            ShortcutDiagnostics.logHealthReport(reason: "log-export")
        }

        let logs = try await fetchLogs()
        let fileURL = try saveLogsToFile(logs)

        logger.notice("🎙️ Log export completed: \(fileURL.path, privacy: .public)")
        return fileURL
    }

    private func fetchLogs() async throws -> [String] {
        let systemInfo = await MainActor.run {
            SystemInfoService.shared.getSystemInfoString()
        }

        let shortcutHealth = await MainActor.run {
            ShortcutDiagnostics.healthReport(reason: "log-export-snapshot")
        }

        let shortcutRingBuffer = ShortcutDiagnostics.recentEventsDump()

        let store = try OSLogStore(scope: .system)
        let predicate = NSPredicate(format: "subsystem == %@", subsystem)

        var logLines: [String] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        let now = Date()
        let windowStart = now.addingTimeInterval(-exportWindow)

        logLines.append("=== VoiceInk Diagnostic Logs ===")
        logLines.append("Export Date: \(dateFormatter.string(from: now))")
        logLines.append("Subsystem: \(subsystem)")
        logLines.append(
            "Log Window: \(dateFormatter.string(from: windowStart)) → \(dateFormatter.string(from: now)) (last \(Int(exportWindow / 60)) min)"
        )
        logLines.append("================================")
        logLines.append("")
        logLines.append(systemInfo)
        logLines.append("")
        logLines.append(shortcutHealth)
        logLines.append("")
        logLines.append("=== SHORTCUT DIAGNOSTIC RING BUFFER (in-memory) ===")
        logLines.append(
            "These events are dual-written in-process so sparse-user bugs still show evidence even if OSLogStore is sparse."
        )
        logLines.append(shortcutRingBuffer)
        logLines.append("=== END SHORTCUT DIAGNOSTIC RING BUFFER ===")
        logLines.append("")

        logLines.append("--- Logs (last \(Int(exportWindow / 60)) min) ---")
        logLines.append("")

        let position = store.position(date: windowStart)
        let entries = try store.getEntries(at: position, matching: predicate)

        var logCount = 0
        for entry in entries {
            guard let logEntry = entry as? OSLogEntryLog else { continue }

            let timestamp = dateFormatter.string(from: logEntry.date)
            let level = logLevelString(logEntry.level)
            let category = logEntry.category
            let message = logEntry.composedMessage

            logLines.append("[\(timestamp)] [\(level)] [\(category)] \(message)")
            logCount += 1
        }

        if logCount == 0 {
            logLines.append("No logs found in this window.")
        }

        logLines.append("")

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
