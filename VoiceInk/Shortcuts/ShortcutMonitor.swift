import AppKit
import CoreGraphics
import Foundation

final class ShortcutMonitor {
    fileprivate enum EventKind {
        case keyDown
        case keyUp
        case flagsChanged
    }

    private struct ShortcutState {
        var shortcut: Shortcut
        var isDown = false
    }

    private var shortcuts: [ShortcutAction: ShortcutState] = [:]
    private var onKeyDown: ((ShortcutAction, TimeInterval) -> Void)?
    private var onKeyUp: ((ShortcutAction, TimeInterval) -> Void)?
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?

    private static var hasRequestedListenEventAccess = false

    deinit {
        stop()
    }

    @discardableResult
    func start(
        shortcuts: [ShortcutAction: Shortcut],
        onKeyDown: @escaping (ShortcutAction, TimeInterval) -> Void,
        onKeyUp: @escaping (ShortcutAction, TimeInterval) -> Void
    ) -> Bool {
        stop()

        for (action, shortcut) in shortcuts {
            self.shortcuts[action] = ShortcutState(shortcut: shortcut)
        }

        guard !self.shortcuts.isEmpty else {
            return true
        }

        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp

        return installEventTap()
    }

    func stop() {
        if let eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
            self.eventTapRunLoopSource = nil
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }

        shortcuts = [:]
        onKeyDown = nil
        onKeyUp = nil
    }

    private func installEventTap() -> Bool {
        guard Self.hasListenEventAccess() else {
            return false
        }

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let monitor = Unmanaged<ShortcutMonitor>.fromOpaque(userInfo).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                monitor.resetPressedShortcutsAfterTapInterruption()
                if let eventTap = monitor.eventTap {
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }

            let shouldSuppress = monitor.handleCGEvent(type: type, event: event)
            return shouldSuppress ? nil : Unmanaged.passUnretained(event)
        }

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            CFMachPortInvalidate(eventTap)
            return false
        }

        self.eventTap = eventTap
        eventTapRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return true
    }

    private static func hasListenEventAccess() -> Bool {
        if CGPreflightListenEventAccess() {
            return true
        }

        guard !hasRequestedListenEventAccess else {
            return false
        }

        hasRequestedListenEventAccess = true
        return CGRequestListenEventAccess()
    }

    private func handleCGEvent(type: CGEventType, event: CGEvent) -> Bool {
        guard let eventKind = EventKind(type) else {
            return false
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let modifierFlags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
        return handleEvent(
            kind: eventKind,
            keyCode: keyCode,
            modifierFlags: modifierFlags,
            eventTime: ProcessInfo.processInfo.systemUptime
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
                break
            case .suppress:
                shouldSuppress = true
            case .keyDown:
                state.isDown = true
                shortcuts[action] = state
                shouldSuppress = true
                dispatchKeyDown(for: action, eventTime: eventTime)
            case .keyUp:
                state.isDown = false
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
                shortcuts[action] = state
                dispatchKeyUp(for: action, eventTime: eventTime)
            }

            return
        }

        if state.shortcut.matchesModifierEvent(keyCode: keyCode, modifierFlags: modifierFlags) {
            state.isDown = true
            shortcuts[action] = state
            dispatchKeyDown(for: action, eventTime: eventTime)
        }
    }

    private func dispatchKeyDown(for action: ShortcutAction, eventTime: TimeInterval) {
        DispatchQueue.main.async { [onKeyDown] in
            onKeyDown?(action, eventTime)
        }
    }

    private func dispatchKeyUp(for action: ShortcutAction, eventTime: TimeInterval) {
        DispatchQueue.main.async { [onKeyUp] in
            onKeyUp?(action, eventTime)
        }
    }

    private static let eventMask: CGEventMask = [
        CGEventType.keyDown,
        CGEventType.keyUp,
        CGEventType.flagsChanged
    ].reduce(CGEventMask(0)) { mask, type in
        mask | (CGEventMask(1) << Int(type.rawValue))
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
