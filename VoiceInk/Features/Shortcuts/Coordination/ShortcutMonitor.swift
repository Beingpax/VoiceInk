import AppKit
import CoreGraphics
import Foundation
import os

final class ShortcutMonitor {
    fileprivate enum EventKind: CustomStringConvertible {
        case keyDown
        case keyUp
        case flagsChanged

        var description: String {
            switch self {
            case .keyDown: return "keyDown"
            case .keyUp: return "keyUp"
            case .flagsChanged: return "flagsChanged"
            }
        }
    }

    private struct ShortcutState {
        var shortcut: Shortcut
        var isDown = false
        var pressedAt: TimeInterval?
        var isInterrupted = false
    }

    private var shortcuts: [ShortcutAction: ShortcutState] = [:]
    private var interruptibleActions: Set<ShortcutAction> = []
    private var onKeyDown: ((ShortcutAction, TimeInterval) -> Void)?
    private var onKeyUp: ((ShortcutAction, TimeInterval) -> Void)?
    private var onShortcutInterrupted: ((ShortcutAction, TimeInterval) -> Void)?
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private var healthWatchdogTask: Task<Void, Never>?
    private var lastEventUptime: TimeInterval?
    private var lastMatchedEventUptime: TimeInterval?
    private let ownerLabel: String
    private let monitorID = String(UUID().uuidString.prefix(8))

    private static let shortcutInterruptionWindow: TimeInterval = 1.0
    private static let healthWatchdogIntervalNanoseconds: UInt64 = 60_000_000_000

    init(ownerLabel: String = "ShortcutMonitor") {
        self.ownerLabel = ownerLabel
    }

    deinit {
        stop(reason: "deinit")
    }

    @discardableResult
    func start(
        shortcuts: [ShortcutAction: Shortcut],
        interruptibleActions: Set<ShortcutAction> = [],
        onKeyDown: @escaping (ShortcutAction, TimeInterval) -> Void,
        onKeyUp: @escaping (ShortcutAction, TimeInterval) -> Void,
        onShortcutInterrupted: ((ShortcutAction, TimeInterval) -> Void)? = nil
    ) -> Bool {
        stop(reason: "restart-before-start")

        for (action, shortcut) in shortcuts {
            self.shortcuts[action] = ShortcutState(shortcut: shortcut)
        }

        let shortcutSummary = Self.shortcutSummary(shortcuts)
        ShortcutDiagnostics.register(owner: ownerLabel, shortcuts: shortcutSummary)
        ShortcutDiagnostics.notice(
            "monitor-start owner=\(ownerLabel) id=\(monitorID) count=\(shortcuts.count) interruptible=\(interruptibleActions.count) shortcuts={\(shortcutSummary)}"
        )
        for (action, shortcut) in shortcuts.sorted(by: { $0.key.storageName < $1.key.storageName }) {
            ShortcutDiagnostics.notice(
                "monitor-register owner=\(ownerLabel) id=\(monitorID) action=\(action.storageName) interruptible=\(interruptibleActions.contains(action)) shortcut=\(shortcut.diagnosticDescription)"
            )
        }

        guard !self.shortcuts.isEmpty else {
            ShortcutDiagnostics.recordInstall(owner: ownerLabel, result: "empty-shortcut-set", tapEnabled: nil)
            ShortcutDiagnostics.notice("monitor-start owner=\(ownerLabel) id=\(monitorID) skipped=no-shortcuts")
            return true
        }

        self.interruptibleActions = interruptibleActions
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        self.onShortcutInterrupted = onShortcutInterrupted

        return installEventTap()
    }

    func stop(reason: String = "requested") {
        healthWatchdogTask?.cancel()
        healthWatchdogTask = nil

        let previousShortcutCount = shortcuts.count
        let previousTapEnabled = eventTap.map { CGEvent.tapIsEnabled(tap: $0) }

        if let eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
            self.eventTapRunLoopSource = nil
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }

        shortcuts = [:]
        interruptibleActions = []
        onKeyDown = nil
        onKeyUp = nil
        onShortcutInterrupted = nil
        lastEventUptime = nil
        lastMatchedEventUptime = nil

        if previousShortcutCount > 0 || previousTapEnabled != nil {
            ShortcutDiagnostics.notice(
                "monitor-stop owner=\(ownerLabel) id=\(monitorID) reason=\(reason) shortcutCount=\(previousShortcutCount) tapEnabled=\(previousTapEnabled.map { String($0) } ?? "unknown")"
            )
        }
        ShortcutDiagnostics.recordStopped(owner: ownerLabel, reason: reason)
    }

    private func installEventTap() -> Bool {
        ShortcutDiagnostics.logEnvironment(reason: "monitor-install.\(ownerLabel)")

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                ShortcutDiagnostics.fault(
                    "event-callback result=missing-user-info eventType=\(type.rawValue)"
                )
                return Unmanaged.passUnretained(event)
            }

            let monitor = Unmanaged<ShortcutMonitor>.fromOpaque(userInfo).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                let reason = type == .tapDisabledByTimeout ? "timeout" : "user-input"
                ShortcutDiagnostics.error(
                    "tap-disabled owner=\(monitor.ownerLabel) id=\(monitor.monitorID) reason=\(reason) pressedActions=\(monitor.pressedActionSummary)"
                )
                ShortcutDiagnostics.recordTapState(owner: monitor.ownerLabel, enabled: false, disabledReason: reason)
                ShortcutDiagnostics.logEnvironment(reason: "tap-disabled.\(monitor.ownerLabel).\(reason)")
                monitor.resetPressedShortcutsAfterTapInterruption()
                if let eventTap = monitor.eventTap {
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                    let isEnabled = CGEvent.tapIsEnabled(tap: eventTap)
                    ShortcutDiagnostics.recordTapState(owner: monitor.ownerLabel, enabled: isEnabled)
                    if isEnabled {
                        ShortcutDiagnostics.notice(
                            "tap-reenabled owner=\(monitor.ownerLabel) id=\(monitor.monitorID) reason=\(reason) result=success"
                        )
                    } else {
                        ShortcutDiagnostics.error(
                            "tap-reenabled owner=\(monitor.ownerLabel) id=\(monitor.monitorID) reason=\(reason) result=failed"
                        )
                    }
                } else {
                    ShortcutDiagnostics.fault(
                        "tap-reenabled owner=\(monitor.ownerLabel) id=\(monitor.monitorID) reason=\(reason) result=missing-port"
                    )
                }
                return Unmanaged.passUnretained(event)
            }

            let shouldSuppress = monitor.handleCGEvent(type: type, event: event)
            return shouldSuppress ? nil : Unmanaged.passUnretained(event)
        }

        guard
            let eventTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: Self.eventMask,
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            ShortcutDiagnostics.recordInstall(owner: ownerLabel, result: "tap-create-failed", tapEnabled: false)
            ShortcutDiagnostics.error(
                "tap-install owner=\(ownerLabel) id=\(monitorID) result=tap-create-failed"
            )
            startHealthWatchdog()
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            CFMachPortInvalidate(eventTap)
            ShortcutDiagnostics.recordInstall(owner: ownerLabel, result: "run-loop-source-failed", tapEnabled: false)
            ShortcutDiagnostics.error(
                "tap-install owner=\(ownerLabel) id=\(monitorID) result=run-loop-source-failed"
            )
            startHealthWatchdog()
            return false
        }

        self.eventTap = eventTap
        eventTapRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        let isEnabled = CGEvent.tapIsEnabled(tap: eventTap)
        ShortcutDiagnostics.recordInstall(owner: ownerLabel, result: "installed", tapEnabled: isEnabled)
        ShortcutDiagnostics.notice(
            "tap-install owner=\(ownerLabel) id=\(monitorID) result=installed enabled=\(isEnabled) shortcutCount=\(shortcuts.count)"
        )
        startHealthWatchdog()
        return isEnabled
    }

    private func handleCGEvent(type: CGEventType, event: CGEvent) -> Bool {
        guard let eventKind = EventKind(type) else {
            return false
        }

        let eventTime = ProcessInfo.processInfo.systemUptime
        lastEventUptime = eventTime
        ShortcutDiagnostics.recordEvent(owner: ownerLabel, matched: false)
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let modifierFlags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
        return handleEvent(
            kind: eventKind,
            keyCode: keyCode,
            modifierFlags: modifierFlags,
            eventTime: eventTime
        )
    }

    private func resetPressedShortcutsAfterTapInterruption() {
        let eventTime = ProcessInfo.processInfo.systemUptime
        let pressedActions = shortcuts.compactMap { action, state in
            state.isDown ? action : nil
        }

        guard !pressedActions.isEmpty else {
            return
        }

        for action in pressedActions {
            if var state = shortcuts[action] {
                state.isDown = false
                state.pressedAt = nil
                state.isInterrupted = false
                shortcuts[action] = state
            }
            dispatchKeyUp(for: action, eventTime: eventTime)
        }
    }

    private func handleEvent(
        kind: EventKind,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        eventTime: TimeInterval
    ) -> Bool {
        var shouldSuppress = false

        if kind == .keyDown {
            handleShortcutInterruptions(keyCode: keyCode, eventTime: eventTime)
        }

        for action in Array(shortcuts.keys) {
            guard var state = shortcuts[action] else {
                continue
            }

            if state.shortcut.isModifierOnly {
                handleModifierOnlyShortcut(
                    action: action,
                    state: state,
                    kind: kind,
                    keyCode: keyCode,
                    modifierFlags: modifierFlags,
                    eventTime: eventTime
                )
                continue
            }

            let transition = transitionForKeyShortcut(
                state.shortcut,
                isDown: state.isDown,
                kind: kind,
                keyCode: keyCode,
                modifierFlags: modifierFlags
            )

            switch transition {
            case .none:
                if kind == .keyDown, keyCode == state.shortcut.keyCode {
                    let actualFlags = Shortcut.normalizedModifierFlags(modifierFlags, forKeyCode: keyCode)
                    ShortcutDiagnostics.notice(
                        "event-near-miss owner=\(ownerLabel) id=\(monitorID) action=\(action.storageName) kind=keyDown reason=modifier-mismatch keyCode=\(keyCode) actualModifiers=0x\(String(actualFlags.rawValue, radix: 16)) expected=\(state.shortcut.diagnosticDescription)"
                    )
                }
                break
            case .suppress:
                shouldSuppress = true
                ShortcutDiagnostics.notice(
                    "event-suppressed owner=\(ownerLabel) id=\(monitorID) action=\(action.storageName) kind=\(kind) reason=already-down-or-flags-held"
                )
            case .keyDown:
                state.isDown = true
                state.pressedAt = eventTime
                state.isInterrupted = false
                shortcuts[action] = state
                shouldSuppress = true
                dispatchKeyDown(for: action, eventTime: eventTime)
            case .keyUp:
                state.isDown = false
                state.pressedAt = nil
                state.isInterrupted = false
                shortcuts[action] = state
                shouldSuppress = true
                dispatchKeyUp(for: action, eventTime: eventTime)
            }
        }

        return shouldSuppress
    }

    private enum ShortcutTransition {
        case none
        case suppress
        case keyDown
        case keyUp
    }

    private func transitionForKeyShortcut(
        _ shortcut: Shortcut,
        isDown: Bool,
        kind: EventKind,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) -> ShortcutTransition {
        switch kind {
        case .keyDown:
            guard shortcut.matchesKeyEvent(keyCode: keyCode, modifierFlags: modifierFlags) else {
                return .none
            }

            return isDown ? .suppress : .keyDown
        case .keyUp:
            return isDown && keyCode == shortcut.keyCode ? .keyUp : .none
        case .flagsChanged:
            guard isDown else {
                return .none
            }

            let currentFlags = Shortcut.normalizedModifierFlags(
                modifierFlags,
                forKeyCode: shortcut.keyCode
            )
            return currentFlags.isSuperset(of: shortcut.modifierFlags) ? .suppress : .keyUp
        }
    }

    private func handleModifierOnlyShortcut(
        action: ShortcutAction,
        state: ShortcutState,
        kind: EventKind,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        eventTime: TimeInterval
    ) {
        var state = state

        guard kind == .flagsChanged else {
            return
        }

        if state.isDown {
            if state.shortcut.shouldReleaseModifierEvent(keyCode: keyCode, modifierFlags: modifierFlags) {
                state.isDown = false
                state.pressedAt = nil
                state.isInterrupted = false
                shortcuts[action] = state
                ShortcutDiagnostics.notice(
                    "modifier-transition owner=\(ownerLabel) id=\(monitorID) action=\(action.storageName) transition=keyUp eventKeyCode=\(keyCode) expected=\(state.shortcut.diagnosticDescription)"
                )
                dispatchKeyUp(for: action, eventTime: eventTime)
            } else if keyCode == state.shortcut.keyCode {
                ShortcutDiagnostics.notice(
                    "modifier-near-miss owner=\(ownerLabel) id=\(monitorID) action=\(action.storageName) state=down reason=release-not-detected eventKeyCode=\(keyCode) modifiers=0x\(String(modifierFlags.rawValue, radix: 16))"
                )
            }

            return
        }

        if state.shortcut.matchesModifierEvent(keyCode: keyCode, modifierFlags: modifierFlags) {
            state.isDown = true
            state.pressedAt = eventTime
            state.isInterrupted = false
            shortcuts[action] = state
            ShortcutDiagnostics.notice(
                "modifier-transition owner=\(ownerLabel) id=\(monitorID) action=\(action.storageName) transition=keyDown eventKeyCode=\(keyCode) expected=\(state.shortcut.diagnosticDescription)"
            )
            dispatchKeyDown(for: action, eventTime: eventTime)
        } else if keyCode == state.shortcut.keyCode {
            let actualFlags = Shortcut.normalizedModifierFlags(modifierFlags, forKeyCode: keyCode)
            ShortcutDiagnostics.notice(
                "modifier-near-miss owner=\(ownerLabel) id=\(monitorID) action=\(action.storageName) state=up reason=flags-mismatch eventKeyCode=\(keyCode) actualModifiers=0x\(String(actualFlags.rawValue, radix: 16)) expected=\(state.shortcut.diagnosticDescription)"
            )
        }
    }

    private func handleShortcutInterruptions(keyCode: UInt16, eventTime: TimeInterval) {
        guard !Shortcut.isModifierKeyCode(keyCode) else {
            return
        }

        for action in interruptibleActions {
            guard var state = shortcuts[action],
                state.isDown,
                !state.isInterrupted,
                let pressedAt = state.pressedAt,
                eventTime - pressedAt <= Self.shortcutInterruptionWindow,
                state.shortcut.isInterruptedByAdditionalKeyDown(keyCode: keyCode)
            else {
                continue
            }

            state.isInterrupted = true
            shortcuts[action] = state
            ShortcutDiagnostics.notice(
                "shortcut-interrupted owner=\(ownerLabel) id=\(monitorID) action=\(action.storageName) additionalKeyCode=\(keyCode) elapsed=\(eventTime - pressedAt)"
            )
            dispatchShortcutInterrupted(for: action, eventTime: eventTime)
        }
    }

    private func dispatchKeyDown(for action: ShortcutAction, eventTime: TimeInterval) {
        lastMatchedEventUptime = eventTime
        ShortcutDiagnostics.recordEvent(owner: ownerLabel, matched: true)
        ShortcutDiagnostics.notice(
            "event-match owner=\(ownerLabel) id=\(monitorID) action=\(action.storageName) transition=keyDown eventUptime=\(eventTime)"
        )
        DispatchQueue.main.async { [onKeyDown] in
            guard let onKeyDown else {
                ShortcutDiagnostics.error(
                    "event-dispatch owner=\(self.ownerLabel) id=\(self.monitorID) action=\(action.storageName) transition=keyDown result=dropped-missing-callback"
                )
                return
            }
            ShortcutDiagnostics.notice(
                "event-dispatch owner=\(self.ownerLabel) id=\(self.monitorID) action=\(action.storageName) transition=keyDown result=callback-invoked queueDelaySeconds=\(ProcessInfo.processInfo.systemUptime - eventTime)"
            )
            onKeyDown(action, eventTime)
        }
    }

    private func dispatchKeyUp(for action: ShortcutAction, eventTime: TimeInterval) {
        lastMatchedEventUptime = eventTime
        ShortcutDiagnostics.recordEvent(owner: ownerLabel, matched: true)
        ShortcutDiagnostics.notice(
            "event-match owner=\(ownerLabel) id=\(monitorID) action=\(action.storageName) transition=keyUp eventUptime=\(eventTime)"
        )
        DispatchQueue.main.async { [onKeyUp] in
            guard let onKeyUp else {
                ShortcutDiagnostics.error(
                    "event-dispatch owner=\(self.ownerLabel) id=\(self.monitorID) action=\(action.storageName) transition=keyUp result=dropped-missing-callback"
                )
                return
            }
            ShortcutDiagnostics.notice(
                "event-dispatch owner=\(self.ownerLabel) id=\(self.monitorID) action=\(action.storageName) transition=keyUp result=callback-invoked queueDelaySeconds=\(ProcessInfo.processInfo.systemUptime - eventTime)"
            )
            onKeyUp(action, eventTime)
        }
    }

    private func dispatchShortcutInterrupted(for action: ShortcutAction, eventTime: TimeInterval) {
        ShortcutDiagnostics.notice(
            "event-dispatch owner=\(ownerLabel) id=\(monitorID) action=\(action.storageName) transition=interrupted eventUptime=\(eventTime)"
        )
        DispatchQueue.main.async { [onShortcutInterrupted] in
            guard let onShortcutInterrupted else {
                ShortcutDiagnostics.notice(
                    "event-dispatch owner=\(self.ownerLabel) id=\(self.monitorID) action=\(action.storageName) transition=interrupted result=dropped-missing-callback"
                )
                return
            }
            ShortcutDiagnostics.notice(
                "event-dispatch owner=\(self.ownerLabel) id=\(self.monitorID) action=\(action.storageName) transition=interrupted result=callback-invoked queueDelaySeconds=\(ProcessInfo.processInfo.systemUptime - eventTime)"
            )
            onShortcutInterrupted(action, eventTime)
        }
    }

    private static let eventMask: CGEventMask = [
        CGEventType.keyDown,
        CGEventType.keyUp,
        CGEventType.flagsChanged,
    ].reduce(CGEventMask(0)) { mask, type in
        mask | (CGEventMask(1) << Int(type.rawValue))
    }

    private var pressedActionSummary: String {
        let actions = shortcuts.compactMap { action, state in
            state.isDown ? action.storageName : nil
        }.sorted()
        return actions.isEmpty ? "none" : actions.joined(separator: ",")
    }

    private func startHealthWatchdog() {
        healthWatchdogTask?.cancel()
        healthWatchdogTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.healthWatchdogIntervalNanoseconds)
                guard !Task.isCancelled, let self else { return }

                guard let eventTap = self.eventTap else {
                    ShortcutDiagnostics.error(
                        "tap-watchdog owner=\(self.ownerLabel) id=\(self.monitorID) result=missing-port shortcutCount=\(self.shortcuts.count)"
                    )
                    ShortcutDiagnostics.recordTapState(owner: self.ownerLabel, enabled: false, disabledReason: "watchdog-missing-port")
                    ShortcutDiagnostics.logEnvironment(reason: "tap-watchdog-missing-port.\(self.ownerLabel)")
                    continue
                }

                let isEnabled = CGEvent.tapIsEnabled(tap: eventTap)
                let currentUptime = ProcessInfo.processInfo.systemUptime
                let lastEventAge = self.lastEventUptime.map { currentUptime - $0 }
                let lastMatchAge = self.lastMatchedEventUptime.map { currentUptime - $0 }
                ShortcutDiagnostics.recordTapState(owner: self.ownerLabel, enabled: isEnabled)
                ShortcutDiagnostics.notice(
                    "tap-watchdog owner=\(self.ownerLabel) id=\(self.monitorID) enabled=\(isEnabled) shortcutCount=\(self.shortcuts.count) pressedActions=\(self.pressedActionSummary) lastEventAgeSeconds=\(lastEventAge.map { String($0) } ?? "never") lastMatchAgeSeconds=\(lastMatchAge.map { String($0) } ?? "never")"
                )
                ShortcutDiagnostics.logEnvironment(reason: "tap-watchdog.\(self.ownerLabel)")
            }
        }
    }

    private static func shortcutSummary(_ shortcuts: [ShortcutAction: Shortcut]) -> String {
        let summary = shortcuts.map { action, shortcut in
            "\(action.storageName)=\(shortcut.diagnosticDescription)"
        }.sorted()
        return summary.isEmpty ? "none" : summary.joined(separator: " | ")
    }
}

private extension ShortcutMonitor.EventKind {
    init?(_ type: CGEventType) {
        switch type {
        case .keyDown:
            self = .keyDown
        case .keyUp:
            self = .keyUp
        case .flagsChanged:
            self = .flagsChanged
        default:
            return nil
        }
    }
}
