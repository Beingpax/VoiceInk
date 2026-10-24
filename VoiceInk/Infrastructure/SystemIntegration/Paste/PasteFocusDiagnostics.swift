import AppKit
import ApplicationServices
import Foundation
import os

/// Best-effort metadata snapshots for every paste. Queries never hold up the paste command.
final class PasteFocusDiagnostics: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "PasteFocusDiagnostics")
    private static let queue = DispatchQueue(label: "com.prakashjoshipax.voiceink.paste-focus", qos: .utility)
    private static let messagingTimeout: Float = 0.02

    private struct Snapshot {
        let processID: pid_t?
        let element: AXUIElement?
        let status: String
        let error: AXError?
        var role: String?
        var subrole: String?
        var editable: Bool?
        var focused: Bool?
        var enabled: Bool?
        var budgetExceeded = false
    }

    private let sessionID: String
    private let startedAt = ProcessInfo.processInfo.systemUptime
    // Accessed only on queue.
    private var nearCommand: Snapshot?

    init(sessionID: String) {
        self.sessionID = sessionID
    }

    func captureAroundPaste(processID: pid_t?, appIdentifier: String) {
        Self.queue.async { [self] in
            // This may overlap or follow event posting; sampleOffsetMs/queryMs describe the observation window.
            nearCommand = capture(processID: processID, appIdentifier: appIdentifier, stage: "command-window")
        }
    }

    @MainActor
    func captureAfterPaste(commandPosted: Bool, commandProcessID: pid_t?) {
        let commandFinishedAt = ProcessInfo.processInfo.systemUptime
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            let app = NSWorkspace.shared.frontmostApplication
            let processID = app?.processIdentifier
            let appIdentifier = app?.bundleIdentifier ?? "unknown"
            Self.queue.async { [self] in
                let afterCommandMs = Int((ProcessInfo.processInfo.systemUptime - commandFinishedAt) * 1_000)
                let after = capture(processID: processID, appIdentifier: appIdentifier, stage: "after-command")
                let focusChanged: String
                if let nearCommand, let nearElement = nearCommand.element, let afterElement = after.element {
                    focusChanged = String(nearCommand.processID != after.processID || !CFEqual(nearElement, afterElement))
                } else {
                    focusChanged = "unknown"
                }
                let commandPID = commandProcessID.map { String($0) } ?? "unknown"
                let appChanged = commandProcessID.flatMap { commandPID in
                    after.processID.map { String(commandPID != $0) }
                } ?? "unknown"
                Self.logger.notice(
                    "Paste focus comparison id=\(self.sessionID, privacy: .public) commandPosted=\(commandPosted, privacy: .public) commandPID=\(commandPID, privacy: .public) appChanged=\(appChanged, privacy: .public) reportedFocusChanged=\(focusChanged, privacy: .public) afterCommandMs=\(afterCommandMs, privacy: .public) insertion=unverified"
                )
            }
        }
    }

    private func capture(processID: pid_t?, appIdentifier: String, stage: String) -> Snapshot {
        let queryStartedAt = ProcessInfo.processInfo.systemUptime
        let snapshot: Snapshot
        if !AXIsProcessTrusted() {
            snapshot = Snapshot(processID: processID, element: nil, status: "accessibility-not-trusted", error: nil)
        } else if let processID {
            let appElement = AXUIElementCreateApplication(processID)
            AXUIElementSetMessagingTimeout(appElement, Self.messagingTimeout)
            let read = AccessibilityFocusReader.focusedElement(in: appElement)
            if let element = read.element {
                AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
                var observed = Snapshot(processID: processID, element: element, status: "element-reported", error: read.error)
                // Bound metadata work as well as each individual AX request. No retries or tree walks.
                let deadline = queryStartedAt + 0.10
                var budgetExceeded = false
                func withinBudget<T>(_ query: () -> T?) -> T? {
                    guard ProcessInfo.processInfo.systemUptime < deadline else {
                        budgetExceeded = true
                        return nil
                    }
                    return query()
                }
                let role = withinBudget { AccessibilityFocusReader.stringAttribute(kAXRoleAttribute as CFString, from: element) }
                observed.role = role
                observed.focused = withinBudget { AccessibilityFocusReader.boolAttribute(kAXFocusedAttribute as CFString, from: element) }
                observed.editable = withinBudget { AccessibilityFocusReader.editableState(of: element, role: role) }
                observed.enabled = withinBudget { AccessibilityFocusReader.boolAttribute(kAXEnabledAttribute as CFString, from: element) }
                observed.subrole = withinBudget { AccessibilityFocusReader.stringAttribute(kAXSubroleAttribute as CFString, from: element) }
                observed.budgetExceeded = budgetExceeded
                snapshot = observed
            } else {
                // A missing/generic Chromium AX tree is not evidence that no text field has focus.
                snapshot = Snapshot(processID: processID, element: nil, status: "unknown", error: read.error)
            }
        } else {
            snapshot = Snapshot(processID: nil, element: nil, status: "no-frontmost-application", error: nil)
        }
        let queryMs = Int((ProcessInfo.processInfo.systemUptime - queryStartedAt) * 1_000)
        let sampleOffsetMs = Int((queryStartedAt - startedAt) * 1_000)
        let pid = processID.map { String($0) } ?? "unknown"
        let error = snapshot.error.map { String($0.rawValue) } ?? "none"
        Self.logger.notice(
            "Paste focus id=\(self.sessionID, privacy: .public) stage=\(stage, privacy: .public) app=\(appIdentifier, privacy: .public) pid=\(pid, privacy: .public) status=\(snapshot.status, privacy: .public) role=\(snapshot.role ?? "unknown", privacy: .public) subrole=\(snapshot.subrole ?? "unknown", privacy: .public) editable=\(Self.describe(snapshot.editable), privacy: .public) focused=\(Self.describe(snapshot.focused), privacy: .public) enabled=\(Self.describe(snapshot.enabled), privacy: .public) axError=\(error, privacy: .public) queryMs=\(queryMs, privacy: .public) sampleOffsetMs=\(sampleOffsetMs, privacy: .public) budgetExceeded=\(snapshot.budgetExceeded, privacy: .public)"
        )
        return snapshot
    }

    private static func describe(_ value: Bool?) -> String {
        value.map { String($0) } ?? "unknown"
    }
}
