import Foundation
import OSLog

/// Correlates one user-triggered recording across shortcut handling, UI, engine,
/// device routing, Core Audio capture, and transcription. This intentionally
/// records metadata and timing only; it never records transcript or PCM content.
final class RecordingDiagnostics: @unchecked Sendable {
    static let shared = RecordingDiagnostics()

    private struct Trace {
        let id: String
        let startedAtNanoseconds: UInt64
        var sequence: UInt64
    }

    private let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "RecordingDiagnostics"
    )
    private let lock = NSLock()
    private var trace: Trace?

    private init() {}

    var currentID: String? {
        lock.lock()
        defer { lock.unlock() }
        return trace?.id
    }

    @discardableResult
    func begin(trigger: String, details: String = "") -> String {
        let now = DispatchTime.now().uptimeNanoseconds
        let id = String(UUID().uuidString.prefix(12))
        var replacedID: String?

        lock.lock()
        replacedID = trace?.id
        trace = Trace(id: id, startedAtNanoseconds: now, sequence: 1)
        lock.unlock()

        if let replacedID {
            logger.warning(
                "DIAG id=\(replacedID, privacy: .public) event=trace-replaced reason=new-recording-trigger"
            )
        }
        logger.notice(
            "DIAG id=\(id, privacy: .public) seq=1 elapsedMs=0.000 event=recording-trigger trigger=\(trigger, privacy: .public) details=\(details, privacy: .public)"
        )
        return id
    }

    @discardableResult
    func beginIfNeeded(trigger: String, details: String = "") -> String {
        if let currentID {
            mark("additional-start-entry", details: "trigger=\(trigger) \(details)")
            return currentID
        }
        return begin(trigger: trigger, details: details)
    }

    func mark(_ event: String, details: String = "") {
        let now = DispatchTime.now().uptimeNanoseconds
        let snapshot: (id: String, sequence: UInt64, startedAt: UInt64)?

        lock.lock()
        if var current = trace {
            current.sequence += 1
            trace = current
            snapshot = (current.id, current.sequence, current.startedAtNanoseconds)
        } else {
            snapshot = nil
        }
        lock.unlock()

        guard let snapshot else { return }
        let elapsedMs = Double(now - snapshot.startedAt) / 1_000_000.0
        logger.notice(
            "DIAG id=\(snapshot.id, privacy: .public) seq=\(snapshot.sequence, privacy: .public) elapsedMs=\(elapsedMs, format: .fixed(precision: 3), privacy: .public) event=\(event, privacy: .public) details=\(details, privacy: .public)"
        )
    }

    func end(expectedID: String? = nil, outcome: String, details: String = "") {
        let now = DispatchTime.now().uptimeNanoseconds
        let snapshot: (id: String, sequence: UInt64, startedAt: UInt64)?
        var mismatchedCurrentID: String?

        lock.lock()
        if var current = trace {
            if let expectedID, expectedID != current.id {
                mismatchedCurrentID = current.id
                snapshot = nil
            } else {
                current.sequence += 1
                snapshot = (current.id, current.sequence, current.startedAtNanoseconds)
                trace = nil
            }
        } else {
            snapshot = nil
        }
        lock.unlock()

        if let expectedID, let mismatchedCurrentID {
            logger.warning(
                "DIAG event=stale-end-ignored expectedID=\(expectedID, privacy: .public) currentID=\(mismatchedCurrentID, privacy: .public) outcome=\(outcome, privacy: .public)"
            )
        }
        guard let snapshot else { return }
        let elapsedMs = Double(now - snapshot.startedAt) / 1_000_000.0
        logger.notice(
            "DIAG id=\(snapshot.id, privacy: .public) seq=\(snapshot.sequence, privacy: .public) elapsedMs=\(elapsedMs, format: .fixed(precision: 3), privacy: .public) event=recording-diagnostic-end outcome=\(outcome, privacy: .public) details=\(details, privacy: .public)"
        )
    }
}

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
        logLines.append("Audio Capture Diagnostic Schema: 2")
        logLines.append("================================")
        logLines.append("DIAGNOSTIC NOTES:")
        logLines.append("- DIAG id groups one user-triggered recording across every app layer.")
        logLines.append("- elapsedMs is measured from the shortcut/UI recording trigger.")
        logLines.append("- Capture timing values are milliseconds; -1 means the event was not observed.")
        logLines.append("- leadingMinus*AudioMs measures PCM already written before that signal threshold appeared.")
        logLines.append("- Signal thresholds are diagnostic levels only; no audio or transcript content is included in logs.")
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
