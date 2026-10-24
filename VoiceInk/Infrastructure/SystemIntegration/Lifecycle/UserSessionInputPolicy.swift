import AppKit
import CoreGraphics
import Foundation
import os

/// Gates global shortcuts by session and lock state.
enum UserSessionInputPolicy {
    // WindowServer's lock flag has no public constant.
    private static let screenIsLockedKey = "CGSSessionScreenIsLocked"
    private static let cache = SessionCache()

    /// Starts session observation before installing taps.
    @MainActor static func startObserving() {
        _ = cache
    }

    /// Cached policy for tap callbacks.
    static var allowsShortcutHandling: Bool {
        cache.allowsInput
    }

    /// Checks live state before dispatch, even if lock notifications are delayed.
    @MainActor static var allowsShortcutDispatch: Bool {
        guard let properties = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }
        return allowsShortcutHandling(sessionProperties: properties)
    }

    static func allowsShortcutHandling(sessionProperties: [String: Any]) -> Bool {
        guard booleanValue(sessionProperties[kCGSessionOnConsoleKey as String]) == true else {
            return false
        }

        guard booleanValue(sessionProperties[kCGSessionLoginDoneKey as String]) == true else {
            return false
        }

        if booleanValue(sessionProperties[screenIsLockedKey]) == true {
            return false
        }

        return true
    }

    private static func booleanValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }

        return (value as? NSNumber)?.boolValue
    }

    private final class SessionCache: NSObject, @unchecked Sendable {
        private struct State: Sendable {
            var hasSession = false
            var onConsole = false
            var loginDone = false
            var isLocked = true
            var revision: UInt64 = 0
            var lockRevision: UInt64 = 0
            var consoleRevision: UInt64 = 0

            var allowsInput: Bool { hasSession && onConsole && loginDone && !isLocked }
        }

        private let state = OSAllocatedUnfairLock(initialState: State())
        private let workspaceCenter = NSWorkspace.shared.notificationCenter
        private let distributedCenter = DistributedNotificationCenter.default()
        private var workspaceObservers: [NSObjectProtocol] = []
        private let refreshTimer: DispatchSourceTimer

        override init() {
            refreshTimer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            super.init()
            // Receive lock changes even while VoiceInk is inactive.
            for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
                distributedCenter.addObserver(
                    self,
                    selector: #selector(screenLockDidChange(_:)),
                    name: Notification.Name(name),
                    object: nil,
                    suspensionBehavior: .deliverImmediately
                )
            }
            workspaceObservers.append(workspaceCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: nil) { [weak self] _ in
                guard let self else { return }
                self.state.withLock { state in
                    state.onConsole = false
                    state.consoleRevision &+= 1
                    state.revision &+= 1
                }
                ShortcutDiagnostics.notice("session event=resigned-active")
            })
            workspaceObservers.append(workspaceCenter.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: nil) { [weak self] _ in
                ShortcutDiagnostics.notice("session event=became-active action=refresh")
                self?.refresh()
            })
            refresh()
            // Reconcile missed notifications off the tap thread.
            refreshTimer.schedule(deadline: .now() + 10, repeating: 10, leeway: .seconds(1))
            refreshTimer.setEventHandler { [weak self] in self?.refresh() }
            refreshTimer.resume()
        }

        var allowsInput: Bool { state.withLock { $0.allowsInput } }

        @objc private func screenLockDidChange(_ notification: Notification) {
            let isLocked = notification.name == Notification.Name("com.apple.screenIsLocked")
            state.withLock { state in
                state.isLocked = isLocked
                state.lockRevision &+= 1
                state.revision &+= 1
            }
            ShortcutDiagnostics.notice("session event=lock-notification locked=\(isLocked)")
        }

        private func refresh() {
            let notifications = state.withLock { (lock: $0.lockRevision, console: $0.consoleRevision) }
            while true {
                let revision = state.withLock { $0.revision }
                let properties = CGSessionCopyCurrentDictionary() as? [String: Any]
                let applied = state.withLock { state in
                    // A notification may have changed the session while it was queried.
                    // Retry immediately so activation never waits for the health timer.
                    guard state.revision == revision else { return false }
                    state.revision &+= 1
                    guard let properties else {
                        state.hasSession = false
                        return true
                    }
                    state.hasSession = true
                    // Keep notifications that arrived during this refresh, even if
                    // WindowServer's dictionary has not caught up with them yet.
                    if state.consoleRevision == notifications.console {
                        state.onConsole = UserSessionInputPolicy.booleanValue(properties[kCGSessionOnConsoleKey as String]) == true
                    }
                    state.loginDone = UserSessionInputPolicy.booleanValue(properties[kCGSessionLoginDoneKey as String]) == true
                    if state.lockRevision == notifications.lock {
                        state.isLocked = UserSessionInputPolicy.booleanValue(properties[UserSessionInputPolicy.screenIsLockedKey]) == true
                    }
                    return true
                }
                if applied { return }
            }
        }

        deinit {
            refreshTimer.cancel()
            for observer in workspaceObservers { workspaceCenter.removeObserver(observer) }
            distributedCenter.removeObserver(self)
        }
    }
}
