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
        let frontmostApplicationName: String
        let frontmostApplicationBundleIdentifier: String

        var summary: String {
            "accessibility=\(accessibilityTrusted) listenEvent=\(listenEventAccess) postEvent=\(postEventAccess) secureEventInput=\(secureEventInputEnabled) frontmostApp=\(frontmostApplicationName)(\(frontmostApplicationBundleIdentifier))"
        }
    }

    private struct MonitorHealth {
        var configuredShortcuts = "none"
        var installResult = "not-started"
        var tapEnabled: Bool?
        var lastEventAt: Date?
        var lastMatchedAt: Date?
        var lastDisabledReason: String?
        var lastUpdateAt = Date()
    }

    private static let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "ShortcutDiagnostics"
    )
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
        return EnvironmentSnapshot(
            accessibilityTrusted: AXIsProcessTrusted(),
            listenEventAccess: CGPreflightListenEventAccess(),
            postEventAccess: CGPreflightPostEventAccess(),
            secureEventInputEnabled: IsSecureEventInputEnabled(),
            frontmostApplicationName: frontmostApplication?.localizedName ?? "unknown",
            frontmostApplicationBundleIdentifier: frontmostApplication?.bundleIdentifier ?? "unknown"
        )
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

    static func recordEvent(owner: String, matched: Bool) {
        updateHealth(owner: owner) { health in
            health.lastEventAt = Date()
            if matched {
                health.lastMatchedAt = Date()
            }
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

        return snapshots.keys.sorted().map { owner in
            guard let health = snapshots[owner] else { return "[\(owner)] unavailable" }
            let enabled = health.tapEnabled.map(String.init) ?? "unknown"
            let lastEvent = health.lastEventAt.map { formatter.string(from: $0) } ?? "never"
            let lastMatch = health.lastMatchedAt.map { formatter.string(from: $0) } ?? "never"
            let disabled = health.lastDisabledReason ?? "none"
            let lastUpdate = formatter.string(from: health.lastUpdateAt)
            return "[\(owner)] install=\(health.installResult) enabled=\(enabled) lastEvent=\(lastEvent) lastMatch=\(lastMatch) lastDisabled=\(disabled) lastUpdate=\(lastUpdate) shortcuts={\(health.configuredShortcuts)}"
        }.joined(separator: "\n")
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
}
