import AppKit
import Combine
import Foundation

@MainActor
final class LifecycleObserver {
    static let shared = LifecycleObserver()

    enum Event: Hashable {
        case audioDeviceChanged
        case systemWillSleep
        case systemDidWake
        case displaysDidWake
        case applicationDidBecomeActive
        case screenConfigurationChanged
    }

    private let events = PassthroughSubject<Event, Never>()
    private var defaultCenterObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    private init() {
        observeDefaultCenter(
            Notification.Name("AudioDeviceChanged"),
            as: .audioDeviceChanged
        )
        observeDefaultCenter(
            NSApplication.didBecomeActiveNotification,
            as: .applicationDidBecomeActive
        )
        observeDefaultCenter(
            NSApplication.didChangeScreenParametersNotification,
            as: .screenConfigurationChanged
        )

        observeWorkspace(
            NSWorkspace.willSleepNotification,
            as: .systemWillSleep
        )
        observeWorkspace(
            NSWorkspace.didWakeNotification,
            as: .systemDidWake
        )
        observeWorkspace(
            NSWorkspace.screensDidWakeNotification,
            as: .displaysDidWake
        )
    }

    func publisher(for event: Event) -> AnyPublisher<Event, Never> {
        publisher(for: [event])
    }

    func publisher(for selectedEvents: Set<Event>) -> AnyPublisher<Event, Never> {
        events
            .filter { selectedEvents.contains($0) }
            .eraseToAnyPublisher()
    }

    private func observeDefaultCenter(_ name: Notification.Name, as event: Event) {
        let observer = NotificationCenter.default.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.events.send(event)
            }
        }
        defaultCenterObservers.append(observer)
    }

    private func observeWorkspace(_ name: Notification.Name, as event: Event) {
        let observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.events.send(event)
            }
        }
        workspaceObservers.append(observer)
    }

    deinit {
        for observer in defaultCenterObservers {
            NotificationCenter.default.removeObserver(observer)
        }

        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            workspaceNotifications.removeObserver(observer)
        }
    }
}
