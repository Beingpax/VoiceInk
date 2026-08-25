import AppKit
import Foundation

@MainActor
final class LifecycleObserver {
    enum Event: String, Hashable {
        case deviceChanged = "device-changed"
        case willSleep = "system-will-sleep"
        case didWake = "system-did-wake"
    }

    private let onInvalidation: (Event) -> Void
    private var deviceObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    init(onInvalidation: @escaping (Event) -> Void) {
        self.onInvalidation = onInvalidation

        deviceObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("AudioDeviceChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.onInvalidation(.deviceChanged)
            }
        }

        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        sleepObserver = workspaceNotifications.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.onInvalidation(.willSleep)
            }
        }
        wakeObserver = workspaceNotifications.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.onInvalidation(.didWake)
            }
        }
    }

    deinit {
        if let deviceObserver {
            NotificationCenter.default.removeObserver(deviceObserver)
        }

        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        if let sleepObserver {
            workspaceNotifications.removeObserver(sleepObserver)
        }
        if let wakeObserver {
            workspaceNotifications.removeObserver(wakeObserver)
        }
    }
}
