import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import os

/// Logs shortcut activity without typed text.
enum ShortcutDiagnostics {
    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "ShortcutDiagnostics")
    private static let errorTimes = OSAllocatedUnfairLock(initialState: [String: TimeInterval]())

    static func notice(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }

    static func warning(_ message: String) {
        logger.warning("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    /// Rate-limits repeated storage errors.
    static func storageError(action: ShortcutAction, operation: String) {
        let key = "\(action.storageName).\(operation)"
        let now = ProcessInfo.processInfo.systemUptime
        let shouldLog = errorTimes.withLock { times in
            if let last = times[key], now - last < 60 { return false }
            times[key] = now
            return true
        }
        if shouldLog {
            error("store action=\(action.storageName) result=\(operation)-failed")
        }
    }

    private struct WeakMonitor {
        weak var value: ShortcutMonitor?
    }

    @MainActor private static var monitors: [String: WeakMonitor] = [:]
    @MainActor private static var lastEnvironment: String?
    @MainActor private static var lastEnvironmentCheck: TimeInterval?
    @MainActor private static var recordingContext: (() -> String)?
    private static let captureAction = OSAllocatedUnfairLock<ShortcutAction?>(initialState: nil)

    @MainActor static func logSessionStart() {
        notice("diagnostics schema=4 processID=\(ProcessInfo.processInfo.processIdentifier) version=\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown") build=\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown") inputTrace=shortcut-monitors")
    }

    @MainActor static func setCaptureAction(_ action: ShortcutAction?) {
        captureAction.withLock { $0 = action }
    }

    static var captureSummary: String {
        captureAction.withLock { $0?.storageName ?? "none" }
    }


    /// Traces shortcut candidates, excluding ordinary typing.
    static func shouldTraceKey(code: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        Shortcut.isFunctionKeyCode(code) || code == UInt16(kVK_Escape) || code == UInt16(kVK_Return)
            || !flags.intersection([.command, .control, .option]).isEmpty
    }

    @MainActor static func register(_ monitor: ShortcutMonitor, owner: String) {
        monitors[owner] = WeakMonitor(value: monitor)
    }

    @MainActor static func setRecordingContext(_ provider: @escaping () -> String) {
        recordingContext = provider
    }

    /// Logs environment changes during recovery.
    @MainActor static func observeEnvironment(reason: String, force: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        if !force, let lastEnvironmentCheck, now - lastEnvironmentCheck < 1 { return }
        lastEnvironmentCheck = now
        let snapshot = environmentSummary()
        guard force || snapshot != lastEnvironment else { return }
        lastEnvironment = snapshot
        notice("environment reason=\(reason) \(snapshot)")
    }

    @MainActor static func environmentSummary() -> String {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let secureInput = IsSecureEventInputEnabled()
        // Secure Input ownership is advisory.
        let reportedPID = secureInput ? (session?["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value : nil
        let reportedOwner = reportedPID.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
        return "accessibility=\(AXIsProcessTrusted()) listenAccess=\(CGPreflightListenEventAccess()) postAccess=\(CGPreflightPostEventAccess()) secureInput=\(secureInput) reportedSecureInputPID=\(reportedPID.map { String($0) } ?? "unknown") reportedSecureInputApp=\(reportedOwner ?? "unknown") sessionAllowsInput=\(UserSessionInputPolicy.allowsShortcutHandling)"
    }

    @MainActor static func healthReport() -> String {
        monitors = monitors.filter { $0.value.value != nil }
        let lines = monitors.keys.sorted().compactMap { owner in
            monitors[owner]?.value.map { "[\(owner)] \($0.diagnosticSummary)" }
        }
        return (["Diagnostics: schema=4 processID=\(ProcessInfo.processInfo.processIdentifier) capture=\(captureSummary)", "Environment: \(environmentSummary())", "Recording: \(recordingContext?() ?? "unavailable")"] + lines).joined(separator: "\n")
    }
}
