import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import os

/// Central shortcut diagnostics: permission probes, dual-write logging (OSLog + in-memory ring),
/// and export-time health reports for sparse-user bug reports.
enum ShortcutDiagnostics {
    private static let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "ShortcutDiagnostics"
    )
    private static let lock = NSLock()
    private static var ringBuffer: [String] = []
    private static let maxRingEntries = 400
    private static var lastPermissionFingerprint: String?

    // MARK: - Dual-write logging

    /// Prefer this over bare Logger for anything needed in support exports.
    /// Writes to OSLog (picked up by LogExporter) and an in-memory ring buffer
    /// (survives even if OSLogStore has no entries for the session).
    static func notice(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        appendRing("NOTICE", message)
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        appendRing("ERROR", message)
    }

    static func fault(_ message: String) {
        logger.fault("\(message, privacy: .public)")
        appendRing("FAULT", message)
    }

    private static func appendRing(_ level: String, _ message: String) {
        let stamp = isoTimestamp()
        let line = "[\(stamp)] [\(level)] \(message)"
        lock.lock()
        ringBuffer.append(line)
        if ringBuffer.count > maxRingEntries {
            ringBuffer.removeFirst(ringBuffer.count - maxRingEntries)
        }
        lock.unlock()
    }

    static func recentEventsDump() -> String {
        lock.lock()
        let lines = ringBuffer
        lock.unlock()

        if lines.isEmpty {
            return "(no in-memory shortcut diagnostic events yet)"
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Permission / environment probe

    struct PermissionSnapshot: Equatable {
        let accessibilityTrusted: Bool
        let listenEventAccess: Bool
        let postEventAccess: Bool
        let secureEventInputEnabled: Bool
        let frontmostAppBundleID: String
        let frontmostAppName: String

        var fingerprint: String {
            "ax=\(accessibilityTrusted) listen=\(listenEventAccess) post=\(postEventAccess) secureInput=\(secureEventInputEnabled)"
        }

        var impliesEventTapLikelyBlocked: Bool {
            !accessibilityTrusted || secureEventInputEnabled
        }

        var humanSummary: String {
            var issues: [String] = []
            if !accessibilityTrusted {
                issues.append("Accessibility NOT granted (required for defaultTap event taps that suppress keys)")
            }
            if !listenEventAccess {
                issues.append(
                    "Listen Event Access NOT granted (Input Monitoring; sometimes required depending on macOS version)"
                )
            }
            if !postEventAccess {
                issues.append("Post Event Access NOT granted (affects simulated key events / paste, not listening)")
            }
            if secureEventInputEnabled {
                issues.append(
                    "Secure Event Input is ON (password fields / some apps block global key monitoring)"
                )
            }
            if issues.isEmpty {
                return "no permission/environment blockers detected"
            }
            return issues.joined(separator: "; ")
        }

        var multiLineDescription: String {
            """
            AccessibilityTrusted: \(accessibilityTrusted)
            ListenEventAccess (Input Monitoring): \(listenEventAccess)
            PostEventAccess: \(postEventAccess)
            SecureEventInputEnabled: \(secureEventInputEnabled)
            FrontmostApp: \(frontmostAppName) (\(frontmostAppBundleID))
            Implication: \(humanSummary)
            """
        }
    }

    static func permissionSnapshot() -> PermissionSnapshot {
        let frontmost = NSWorkspace.shared.frontmostApplication
        return PermissionSnapshot(
            accessibilityTrusted: AXIsProcessTrusted(),
            listenEventAccess: CGPreflightListenEventAccess(),
            postEventAccess: CGPreflightPostEventAccess(),
            secureEventInputEnabled: IsSecureEventInputEnabled(),
            frontmostAppBundleID: frontmost?.bundleIdentifier ?? "unknown",
            frontmostAppName: frontmost?.localizedName ?? "unknown"
        )
    }

    /// Log permission snapshot if it changed since last probe (or always when forced).
    @discardableResult
    static func logPermissionSnapshot(reason: String, force: Bool = false) -> PermissionSnapshot {
        let snapshot = permissionSnapshot()
        let fingerprint = snapshot.fingerprint

        lock.lock()
        let previous = lastPermissionFingerprint
        if force || previous != fingerprint {
            lastPermissionFingerprint = fingerprint
            lock.unlock()
            notice(
                "permissions [\(reason)]: \(fingerprint) frontmost=\(snapshot.frontmostAppName)(\(snapshot.frontmostAppBundleID)) → \(snapshot.humanSummary)"
            )
            if snapshot.impliesEventTapLikelyBlocked {
                error(
                    "permissions [\(reason)]: shortcuts likely broken — \(snapshot.humanSummary)"
                )
            }
        } else {
            lock.unlock()
        }

        return snapshot
    }

    // MARK: - Configuration health

    struct ConfigurationSnapshot {
        let primarySelection: String
        let primaryShortcut: String
        let primaryMode: String
        let secondarySelection: String
        let secondaryShortcut: String
        let secondaryMode: String
        let primaryConfigured: Bool
        let issues: [String]

        var multiLineDescription: String {
            let issueText = issues.isEmpty ? "none" : issues.joined(separator: "; ")
            return """
                PrimarySelection: \(primarySelection)
                PrimaryShortcut: \(primaryShortcut)
                PrimaryMode: \(primaryMode)
                PrimaryConfigured: \(primaryConfigured)
                SecondarySelection: \(secondarySelection)
                SecondaryShortcut: \(secondaryShortcut)
                SecondaryMode: \(secondaryMode)
                ConfigIssues: \(issueText)
                """
        }
    }

    static func configurationSnapshot() -> ConfigurationSnapshot {
        let primarySelection =
            UserDefaults.standard.string(forKey: "primaryRecordingShortcut") ?? "unset"
        let secondarySelection =
            UserDefaults.standard.string(forKey: "secondaryRecordingShortcut") ?? "unset"
        let primaryMode =
            UserDefaults.standard.string(forKey: "primaryRecordingShortcutMode") ?? "unset"
        let secondaryMode =
            UserDefaults.standard.string(forKey: "secondaryRecordingShortcutMode") ?? "unset"

        let primary = ShortcutStore.rawShortcut(for: .primaryRecording)
        let secondary = ShortcutStore.rawShortcut(for: .secondaryRecording)
        let primaryCleared = ShortcutStore.isShortcutCleared(for: .primaryRecording)
        let secondaryCleared = ShortcutStore.isShortcutCleared(for: .secondaryRecording)

        var issues: [String] = []

        if primarySelection == "custom" || primarySelection == "unset" {
            if primary == nil {
                issues.append(
                    "primary selection is custom/unset but no Shortcut_primaryRecording data stored"
                )
            }
            if primaryCleared && primary == nil {
                issues.append("primary shortcut marked cleared")
            }
        }

        if secondarySelection == "custom", secondary == nil {
            issues.append(
                "secondary selection is custom but no Shortcut_secondaryRecording data stored"
            )
        }

        if secondaryCleared && secondarySelection == "custom" {
            issues.append("secondary shortcut marked cleared while selection is custom")
        }

        let primaryConfigured = primary != nil && primarySelection != "none"

        return ConfigurationSnapshot(
            primarySelection: primarySelection,
            primaryShortcut: primary?.diagnosticDescription
                ?? (primaryCleared ? "cleared" : "nil"),
            primaryMode: primaryMode,
            secondarySelection: secondarySelection,
            secondaryShortcut: secondary?.diagnosticDescription
                ?? (secondaryCleared ? "cleared" : "nil"),
            secondaryMode: secondaryMode,
            primaryConfigured: primaryConfigured,
            issues: issues
        )
    }

    // MARK: - Full health report (export / system info)

    static func healthReport(reason: String) -> String {
        let permissions = logPermissionSnapshot(reason: reason, force: true)
        let config = configurationSnapshot()
        let taps = ShortcutMonitor.allOwnersInstallSummary
        let live = ShortcutMonitor.allOwnersLiveTapSummary

        if !config.issues.isEmpty {
            error("config health [\(reason)]: \(config.issues.joined(separator: "; "))")
        }

        if let recordingOK = ShortcutMonitor.installSucceededByOwnerValue(for: "Recording"),
            !recordingOK
        {
            error(
                "event tap health [\(reason)]: Recording tap failed to install — global shortcuts cannot fire"
            )
        }

        return """
            === SHORTCUT HEALTH REPORT (\(reason)) ===
            Generated: \(isoTimestamp())
            --- Permissions ---
            \(permissions.multiLineDescription.trimmingCharacters(in: .whitespacesAndNewlines))
            --- Configuration ---
            \(config.multiLineDescription.trimmingCharacters(in: .whitespacesAndNewlines))
            --- Event Taps (install) ---
            \(taps)
            --- Event Taps (live enabled) ---
            \(live)
            === END SHORTCUT HEALTH REPORT ===
            """
    }

    static func logHealthReport(reason: String) {
        let report = healthReport(reason: reason)
        // Split so OSLog doesn't truncate huge multi-line strings as badly.
        for line in report.split(separator: "\n", omittingEmptySubsequences: false) {
            notice(String(line))
        }
    }

    private static func isoTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}
