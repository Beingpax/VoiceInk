import Foundation
import OSLog

final class LogExporter {
    static let shared = LogExporter()

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "LogExporter")
    private let subsystem = "com.prakashjoshipax.voiceink"
    private let fluidAudioSubsystem = "com.fluidinference"
    private let exportWindow: TimeInterval = 30 * 60

    private init() {
        UserDefaults.standard.removeObject(forKey: "logExporter.sessionStartDates.v1")
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
        let exportDate = Date()
        let startDate = exportDate.addingTimeInterval(-exportWindow)
        let systemInfo = await MainActor.run {
            SystemInfoService.shared.getSystemInfoString()
        }

        let store = try OSLogStore(scope: .system)
        let processName = ProcessInfo.processInfo.processName
        let predicate = NSPredicate(format: "subsystem IN %@", [subsystem, fluidAudioSubsystem])

        var logLines: [String] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        logLines.append("=== VoiceInk Diagnostic Logs ===")
        logLines.append("Export Date: \(dateFormatter.string(from: exportDate))")
        logLines.append("Subsystems: \(subsystem), \(fluidAudioSubsystem)")
        logLines.append("FluidAudio Process: \(processName)")
        logLines.append("Log Window: Last 30 minutes")
        logLines.append("From: \(dateFormatter.string(from: startDate))")
        logLines.append("To: \(dateFormatter.string(from: exportDate))")
        logLines.append("================================")
        logLines.append("")
        logLines.append(systemInfo)
        logLines.append("")

        let position = store.position(date: startDate)
        let entries = try store.getEntries(at: position, matching: predicate)
        var logCount = 0

        for entry in entries {
            guard let logEntry = entry as? OSLogEntryLog else { continue }
            guard logEntry.date >= startDate else { continue }
            if logEntry.date > exportDate { break }
            // Keep SDK logs from this app, including launches earlier in the window.
            // Other apps can also use FluidAudio's shared subsystem.
            if logEntry.subsystem == fluidAudioSubsystem, logEntry.process != processName { continue }

            let timestamp = dateFormatter.string(from: logEntry.date)
            let level = logLevelString(logEntry.level)
            let category = logEntry.category
            let message = logEntry.composedMessage

            logLines.append("[\(timestamp)] [\(level)] [\(logEntry.subsystem)] [\(category)] \(message)")
            logCount += 1
        }

        if logCount == 0 {
            logLines.append("No VoiceInk logs found in the last 30 minutes.")
        }

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
