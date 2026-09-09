import ApplicationServices
import Foundation

private final class AutoLearnFocusCallbackBridge: @unchecked Sendable {
    let token: AutoLearnPasteToken
    let handler: @Sendable (AutoLearnPasteToken) -> Void

    init(token: AutoLearnPasteToken, handler: @escaping @Sendable (AutoLearnPasteToken) -> Void) {
        self.token = token
        self.handler = handler
    }

    func notify() {
        handler(token)
    }
}

private let autoLearnFocusCallback: AXObserverCallback = { _, _, _, refcon in
    guard let refcon else { return }
    let bridge = Unmanaged<AutoLearnFocusCallbackBridge>.fromOpaque(refcon).takeUnretainedValue()
    bridge.notify()
}

final class AutoLearnFocusObserver: @unchecked Sendable {
    private struct State {
        var generation: UUID?
        var runLoop: CFRunLoop?
    }

    private let lock = NSLock()
    private var state = State()

    func start(
        processID: pid_t,
        token: AutoLearnPasteToken,
        handler: @escaping @Sendable (AutoLearnPasteToken) -> Void
    ) {
        stop()

        let generation = UUID()
        withLock {
            state.generation = generation
            state.runLoop = nil
        }

        let thread = Thread { [weak self] in
            self?.run(
                processID: processID,
                token: token,
                generation: generation,
                handler: handler
            )
        }
        thread.name = "VoiceInk Auto Learn Focus Observer"
        thread.qualityOfService = .utility
        thread.start()
    }

    func stop() {
        let runLoop = withLock { () -> CFRunLoop? in
            state.generation = nil
            let runLoop = state.runLoop
            state.runLoop = nil
            return runLoop
        }

        if let runLoop {
            CFRunLoopStop(runLoop)
            CFRunLoopWakeUp(runLoop)
        }
    }

    deinit {
        stop()
    }

    private func run(
        processID: pid_t,
        token: AutoLearnPasteToken,
        generation: UUID,
        handler: @escaping @Sendable (AutoLearnPasteToken) -> Void
    ) {
        autoreleasepool {
            let appElement = AXUIElementCreateApplication(processID)
            AXUIElementSetMessagingTimeout(appElement, AutoLearnLimits.accessibilityTimeoutSeconds)

            var observer: AXObserver?
            guard AXObserverCreate(processID, autoLearnFocusCallback, &observer) == .success,
                let observer
            else {
                clearState(for: generation)
                return
            }

            let bridge = AutoLearnFocusCallbackBridge(token: token, handler: handler)
            let refcon = Unmanaged.passRetained(bridge).toOpaque()
            let requestedNotifications = [
                kAXFocusedUIElementChangedNotification as String,
                kAXFocusedWindowChangedNotification as String,
                kAXApplicationDeactivatedNotification as String,
            ]
            var registeredNotifications: [String] = []

            for notification in requestedNotifications {
                if AXObserverAddNotification(observer, appElement, notification as CFString, refcon) == .success {
                    registeredNotifications.append(notification)
                }
            }

            guard !registeredNotifications.isEmpty else {
                Unmanaged<AutoLearnFocusCallbackBridge>.fromOpaque(refcon).release()
                clearState(for: generation)
                return
            }

            let runLoop = CFRunLoopGetCurrent()
            let source = AXObserverGetRunLoopSource(observer)
            CFRunLoopAddSource(runLoop, source, .defaultMode)

            let shouldRun = withLock { () -> Bool in
                guard state.generation == generation else { return false }
                state.runLoop = runLoop
                return true
            }

            if shouldRun {
                CFRunLoopRun()
            }

            CFRunLoopRemoveSource(runLoop, source, .defaultMode)
            for notification in registeredNotifications {
                AXObserverRemoveNotification(observer, appElement, notification as CFString)
            }
            Unmanaged<AutoLearnFocusCallbackBridge>.fromOpaque(refcon).release()
            clearState(for: generation)
        }
    }

    private func clearState(for generation: UUID) {
        withLock {
            guard state.generation == generation else { return }
            state.generation = nil
            state.runLoop = nil
        }
    }

    private func withLock<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}
