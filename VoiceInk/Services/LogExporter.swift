import Foundation
import OSLog

final class LogExporter {
    static let shared = LogExporter()

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "LogExporter")
    private let subsystem = "com.prakashjoshipax.voiceink"
    private let diagnosticWindowMinutes = 30

    private init() {}

    func exportLogs() async throws -> URL {
        logger.notice("🎙️ Starting log export")

        let logs = try await fetchLogs()
        let fileURL = try saveLogsToFile(logs)

        logger.notice("🎙️ Log export completed: \(fileURL.path, privacy: .public)")
        return fileURL
    }

    private func fetchLogs() async throws -> [String] {
        let systemInfo = await MainActor.run {
            SystemInfoService.shared.getSystemInfoString()
        }

        let store = try OSLogStore(scope: .system)
        let predicate = NSPredicate(format: "subsystem == %@", subsystem)

        var logLines: [String] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let exportDate = Date()
        let startDate = exportDate.addingTimeInterval(-Double(diagnosticWindowMinutes * 60))

        logLines.append("=== VoiceInk Diagnostic Logs ===")
        logLines.append("Export Date: \(dateFormatter.string(from: exportDate))")
        logLines.append("Subsystem: \(subsystem)")
        logLines.append("Log Window: Last \(diagnosticWindowMinutes) minutes")
        logLines.append("Window Start: \(dateFormatter.string(from: startDate))")
        logLines.append("================================")
        logLines.append("")
        logLines.append(systemInfo)
        logLines.append("")
        logLines.append("--- VoiceInk Events ---")
        logLines.append("")

        let position = store.position(date: startDate)
        let entries = try store.getEntries(at: position, matching: predicate)
        var logCount = 0

        for entry in entries {
            guard let logEntry = entry as? OSLogEntryLog,
                logEntry.date <= exportDate
            else {
                continue
            }

            let timestamp = dateFormatter.string(from: logEntry.date)
            let level = logLevelString(logEntry.level)
            let category = logEntry.category
            let message = logEntry.composedMessage

            logLines.append("[\(timestamp)] [\(level)] [\(category)] \(message)")
            logCount += 1
        }

        if logCount == 0 {
            logLines.append("No VoiceInk logs found in the last \(diagnosticWindowMinutes) minutes.")
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
