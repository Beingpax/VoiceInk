import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import OSLog

/// Structured, privacy-safe diagnostics for the global shortcut pipeline.
///
/// These records intentionally contain key codes, modifier masks, action names,
/// state transitions, and event-tap health only. They never contain typed text.
enum ShortcutDiagnostics {
    struct EnvironmentSnapshot: Sendable {
        let accessibilityTrusted: Bool
        let listenEventAccess: Bool
        let postEventAccess: Bool
        let secureEventInputEnabled: Bool
        let reportedSecureInputOwnerPID: pid_t?
        let reportedSecureInputOwnerName: String
        let reportedSecureInputOwnerBundleIdentifier: String
        let frontmostApplicationName: String
        let frontmostApplicationBundleIdentifier: String

        var summary: String {
            let reportedOwner = reportedSecureInputOwnerPID.map { pid in
                "pid=\(pid),name=\(reportedSecureInputOwnerName),bundle=\(reportedSecureInputOwnerBundleIdentifier)"
            } ?? "unavailable"
            return "accessibility=\(accessibilityTrusted) listenEvent=\(listenEventAccess) postEvent=\(postEventAccess) secureEventInput=\(secureEventInputEnabled) reportedSecureInputOwner={\(reportedOwner)} frontmostApp=\(frontmostApplicationName)(\(frontmostApplicationBundleIdentifier))"
        }
    }

    private struct MonitorHealth {
        var configuredShortcuts = "none"
        var installResult = "not-started"
        var tapEnabled: Bool?
        var lastEventAt: Date?
        var lastMatchedAt: Date?
        var keyDownEventCount = 0
        var keyUpEventCount = 0
        var flagsChangedEventCount = 0
        var lastKeyDownAt: Date?
        var lastKeyUpAt: Date?
        var lastFlagsChangedAt: Date?
        var lastDisabledReason: String?
        var lastUpdateAt = Date()
    }

    private static let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "ShortcutDiagnostics"
    )
    // This session key is diagnostic-only and can be absent or misattributed by macOS.
    private static let reportedSecureInputPIDKey = "kCGSSessionSecureInputPID"
    private static let processID = ProcessInfo.processInfo.processIdentifier
    private static let healthLock = NSLock()
    nonisolated(unsafe) private static var monitorHealthByOwner: [String: MonitorHealth] = [:]

    static func notice(_ message: String) {
        logger.notice("pid=\(processID, privacy: .public) \(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("pid=\(processID, privacy: .public) \(message, privacy: .public)")
    }

    static func fault(_ message: String) {
        logger.fault("pid=\(processID, privacy: .public) \(message, privacy: .public)")
    }

    static func environmentSnapshot() -> EnvironmentSnapshot {
        let frontmostApplication = MainActor.assumeIsolated {
            NSWorkspace.shared.frontmostApplication
        }
        let secureEventInputEnabled = secureEventInputEnabled()
        let reportedOwner = secureEventInputEnabled ? reportedSecureInputOwner() : nil
        return EnvironmentSnapshot(
            accessibilityTrusted: AXIsProcessTrusted(),
            listenEventAccess: CGPreflightListenEventAccess(),
            postEventAccess: CGPreflightPostEventAccess(),
            secureEventInputEnabled: secureEventInputEnabled,
            reportedSecureInputOwnerPID: reportedOwner?.pid,
            reportedSecureInputOwnerName: reportedOwner?.name ?? "unknown",
            reportedSecureInputOwnerBundleIdentifier: reportedOwner?.bundleIdentifier ?? "unknown",
            frontmostApplicationName: frontmostApplication?.localizedName ?? "unknown",
            frontmostApplicationBundleIdentifier: frontmostApplication?.bundleIdentifier ?? "unknown"
        )
    }

    static func secureEventInputEnabled() -> Bool {
        IsSecureEventInputEnabled()
    }

    static func logEnvironment(reason: String) {
        notice("environment reason=\(reason) \(environmentSnapshot().summary)")
    }

    static func register(owner: String, shortcuts: String) {
        updateHealth(owner: owner) { health in
            health.configuredShortcuts = shortcuts.isEmpty ? "none" : shortcuts
            health.installResult = "starting"
            health.tapEnabled = nil
            health.lastDisabledReason = nil
        }
    }

    static func recordInstall(owner: String, result: String, tapEnabled: Bool?) {
        updateHealth(owner: owner) { health in
            health.installResult = result
            health.tapEnabled = tapEnabled
        }
    }

    static func recordEvent(owner: String, type: CGEventType) {
        let eventDate = Date()
        updateHealth(owner: owner) { health in
            health.lastEventAt = eventDate
            switch type {
            case .keyDown:
                health.keyDownEventCount += 1
                health.lastKeyDownAt = eventDate
            case .keyUp:
                health.keyUpEventCount += 1
                health.lastKeyUpAt = eventDate
            case .flagsChanged:
                health.flagsChangedEventCount += 1
                health.lastFlagsChangedAt = eventDate
            default:
                break
            }
        }
    }

    static func recordMatch(owner: String) {
        updateHealth(owner: owner) { health in
            health.lastMatchedAt = Date()
        }
    }

    static func recordTapState(owner: String, enabled: Bool, disabledReason: String? = nil) {
        updateHealth(owner: owner) { health in
            health.tapEnabled = enabled
            if let disabledReason {
                health.lastDisabledReason = disabledReason
            }
        }
    }

    static func recordStopped(owner: String, reason: String) {
        updateHealth(owner: owner) { health in
            health.installResult = "stopped(\(reason))"
            health.tapEnabled = false
        }
    }

    static func healthReport() -> String {
        healthLock.lock()
        let snapshots = monitorHealthByOwner
        healthLock.unlock()

        guard !snapshots.isEmpty else {
            return "No shortcut monitors have registered in this process."
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let reportDate = Date()

        return snapshots.keys.sorted().map { owner in
            guard let health = snapshots[owner] else { return "[\(owner)] unavailable" }
            let enabled = health.tapEnabled.map(String.init) ?? "unknown"
            let lastEvent = health.lastEventAt.map { formatter.string(from: $0) } ?? "never"
            let lastMatch = health.lastMatchedAt.map { formatter.string(from: $0) } ?? "never"
            let disabled = health.lastDisabledReason ?? "none"
            let lastUpdate = formatter.string(from: health.lastUpdateAt)
            let eventActivity = eventActivitySummary(for: health, referenceDate: reportDate)
            return "[\(owner)] install=\(health.installResult) enabled=\(enabled) lastEvent=\(lastEvent) lastMatch=\(lastMatch) eventTypes={\(eventActivity)} lastDisabled=\(disabled) lastUpdate=\(lastUpdate) shortcuts={\(health.configuredShortcuts)}"
        }.joined(separator: "\n")
    }

    static func eventActivitySummary(owner: String) -> String {
        healthLock.lock()
        let health = monitorHealthByOwner[owner]
        healthLock.unlock()

        guard let health else {
            return "unavailable"
        }
        return eventActivitySummary(for: health, referenceDate: Date())
    }

    static func logHealthReport(reason: String) {
        notice("health-report begin reason=\(reason)")
        for line in healthReport().split(separator: "\n", omittingEmptySubsequences: false) {
            notice("health-report \(line)")
        }
        logEnvironment(reason: "health-report.\(reason)")
        notice("health-report end reason=\(reason)")
    }

    private static func updateHealth(owner: String, update: (inout MonitorHealth) -> Void) {
        healthLock.lock()
        var health = monitorHealthByOwner[owner] ?? MonitorHealth()
        update(&health)
        health.lastUpdateAt = Date()
        monitorHealthByOwner[owner] = health
        healthLock.unlock()
    }

    private static func eventActivitySummary(for health: MonitorHealth, referenceDate: Date) -> String {
        "keyDownCount=\(health.keyDownEventCount) lastKeyDownAgeSeconds=\(ageSummary(health.lastKeyDownAt, referenceDate: referenceDate)) "
            + "keyUpCount=\(health.keyUpEventCount) lastKeyUpAgeSeconds=\(ageSummary(health.lastKeyUpAt, referenceDate: referenceDate)) "
            + "flagsChangedCount=\(health.flagsChangedEventCount) lastFlagsChangedAgeSeconds=\(ageSummary(health.lastFlagsChangedAt, referenceDate: referenceDate))"
    }

    private static func ageSummary(_ date: Date?, referenceDate: Date) -> String {
        guard let date else {
            return "never"
        }
        return String(max(0, referenceDate.timeIntervalSince(date)))
    }

    private static func reportedSecureInputOwner() -> (pid: pid_t, name: String, bundleIdentifier: String)? {
        guard
            let session = CGSessionCopyCurrentDictionary() as? [String: Any],
            let pidNumber = session[reportedSecureInputPIDKey] as? NSNumber
        else {
            return nil
        }

        let pid = pid_t(pidNumber.int32Value)
        guard pid > 0 else {
            return nil
        }

        let application = NSRunningApplication(processIdentifier: pid)
        return (
            pid: pid,
            name: application?.localizedName ?? "unknown",
            bundleIdentifier: application?.bundleIdentifier ?? "unknown"
        )
    }
}
