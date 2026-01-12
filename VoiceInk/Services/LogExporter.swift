import Foundation
import OSLog

final class LogExporter {
    static let shared = LogExporter()

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "LogExporter")
    private let subsystem = "com.prakashjoshipax.voiceink"
    private let maxSessionsToKeep = 3
    private let sessionsKey = "logExporter.sessionStartDates.v1"

    private(set) var sessionStartDates: [Date] = []

    private init() {
        var loadedDates: [Date] = []
        if let data = UserDefaults.standard.data(forKey: sessionsKey),
           let dates = try? JSONDecoder().decode([Date].self, from: data) {
            loadedDates = dates
        }

        sessionStartDates = [Date()] + loadedDates
        sessionStartDates = Array(sessionStartDates.prefix(maxSessionsToKeep))
        saveSessions()

        logger.notice("🎙️ LogExporter initialized, \(self.sessionStartDates.count) session(s) tracked")
    }

    private func saveSessions() {
        if let data = try? JSONEncoder().encode(sessionStartDates) {
            UserDefaults.standard.set(data, forKey: sessionsKey)
        }
    }

    func exportLogs() async throws -> URL {
        logger.notice("🎙️ Starting log export")

        let logs = try await fetchLogs()
        let fileURL = try saveLogsToFile(logs)

        logger.notice("🎙️ Log export completed: \(fileURL.path)")
        return fileURL
    }

    private func fetchLogs() async throws -> [String] {
        let store = try OSLogStore(scope: .system)
        let predicate = NSPredicate(format: "subsystem == %@", subsystem)

        var logLines: [String] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        logLines.append("=== VoiceInk Diagnostic Logs ===")
        logLines.append("Export Date: \(dateFormatter.string(from: Date()))")
        logLines.append("Subsystem: \(subsystem)")
        logLines.append("Total Sessions: \(sessionStartDates.count)")
        logLines.append("================================")
        logLines.append("")

        // Build session ranges with labels
        let totalSessions = sessionStartDates.count
        var sessionRanges: [(label: String, start: Date, end: Date?)] = []

        for i in 0..<totalSessions {
            let start = sessionStartDates[i]
            let end: Date? = (i == 0) ? nil : sessionStartDates[i - 1]
            let sessionNumber = totalSessions - i

            let label: String
            if totalSessions == 1 {
                label = "Session 1 (Current)"
            } else if i == 0 {
                label = "Session \(sessionNumber) (Current)"
            } else if i == totalSessions - 1 {
                label = "Session 1 (Oldest)"
            } else {
                label = "Session \(sessionNumber)"
            }

            sessionRanges.append((label, start, end))
        }

        // Fetch logs for each session (oldest first for chronological order)
        for (label, startDate, endDate) in sessionRanges.reversed() {
            logLines.append("--- \(label) ---")
            logLines.append("")

            let position = store.position(date: startDate)
            let entries = try store.getEntries(at: position, matching: predicate)

            var sessionLogCount = 0
            for entry in entries {
                guard let logEntry = entry as? OSLogEntryLog else { continue }

                if let endDate, logEntry.date >= endDate { break }

                let timestamp = dateFormatter.string(from: logEntry.date)
                let level = logLevelString(logEntry.level)
                let category = logEntry.category
                let message = logEntry.composedMessage

                logLines.append("[\(timestamp)] [\(level)] [\(category)] \(message)")
                sessionLogCount += 1
            }

            if sessionLogCount == 0 {
                logLines.append("No logs found for this session.")
            }

            logLines.append("")
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
            throw NSError(domain: "LogExporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Downloads directory unavailable"])
        }

        let fileURL = downloadsURL.appendingPathComponent(fileName)
        let content = logs.joined(separator: "\n")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        return fileURL
    }
}
