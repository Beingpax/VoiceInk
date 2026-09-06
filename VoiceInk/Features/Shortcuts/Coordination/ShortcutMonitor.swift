import AppKit
import CoreGraphics
import Foundation
import os

final class ShortcutMonitor {
    fileprivate enum EventKind: CustomStringConvertible {
        case keyDown
        case keyUp
        case flagsChanged
        case mouseDown
        case mouseDragged
        case mouseUp

        var description: String {
            switch self {
            case .keyDown: return "keyDown"
            case .keyUp: return "keyUp"
            case .flagsChanged: return "flagsChanged"
            case .mouseDown: return "mouseDown"
            case .mouseDragged: return "mouseDragged"
            case .mouseUp: return "mouseUp"
            }
        }
    }

    private struct ShortcutState {
        var shortcut: Shortcut
        var isDown = false
        var pressedAt: TimeInterval?
        var isInterrupted = false
        var requiresStandaloneRelease = false
    }

    private var shortcuts: [ShortcutAction: ShortcutState] = [:]
    private var pressedKeyCodes = Set<UInt16>()
    private var suppressedMouseButtons = Set<UInt16>()
    private var interruptibleActions: Set<ShortcutAction> = []
    private var standaloneModifierActions: Set<ShortcutAction> = []
    private var onShortcutDown: ((ShortcutAction, TimeInterval) -> Void)?
    private var onShortcutUp: ((ShortcutAction, TimeInterval) -> Void)?
    private var onShortcutInterrupted: ((ShortcutAction, TimeInterval) -> Void)?
    private var onStandaloneModifierChord: ((ShortcutAction) -> Void)?
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
        standaloneModifierActions: Set<ShortcutAction> = [],
        onShortcutDown: @escaping (ShortcutAction, TimeInterval) -> Void,
        onShortcutUp: @escaping (ShortcutAction, TimeInterval) -> Void,
        onShortcutInterrupted: ((ShortcutAction, TimeInterval) -> Void)? = nil,
        onStandaloneModifierChord: ((ShortcutAction) -> Void)? = nil
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
        self.standaloneModifierActions = standaloneModifierActions
        self.onShortcutDown = onShortcutDown
        self.onShortcutUp = onShortcutUp
        self.onShortcutInterrupted = onShortcutInterrupted
        self.onStandaloneModifierChord = onStandaloneModifierChord

        return installEventTap()
    }

    func updateStandaloneModifierActions(_ actions: Set<ShortcutAction>) {
        standaloneModifierActions = actions
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
        pressedKeyCodes = []
        suppressedMouseButtons = []
        interruptibleActions = []
        standaloneModifierActions = []
        onShortcutDown = nil
        onShortcutUp = nil
        onShortcutInterrupted = nil
        onStandaloneModifierChord = nil
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
        guard UserSessionInputPolicy.allowsShortcutHandling else {
            clearPressedShortcutState()
            return false
        }

        guard let eventKind = EventKind(type) else {
            return false
        }

        let eventTime = ProcessInfo.processInfo.systemUptime
        lastEventUptime = eventTime
        ShortcutDiagnostics.recordEvent(owner: ownerLabel, type: type)
        let inputCode: UInt16
        switch eventKind {
        case .keyDown, .keyUp, .flagsChanged:
            inputCode = UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode))
        case .mouseDown, .mouseDragged, .mouseUp:
            inputCode = UInt16(clamping: event.getIntegerValueField(.mouseEventButtonNumber))
        }

        let modifierFlags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
        return handleEvent(
            kind: eventKind,
            inputCode: inputCode,
            modifierFlags: modifierFlags,
            eventTime: eventTime
        )
    }

    private func resetPressedShortcutsAfterTapInterruption() {
        releasePressedShortcuts(eventTime: ProcessInfo.processInfo.systemUptime)
    }

    private func clearPressedShortcutState() {
        releasePressedShortcuts(eventTime: ProcessInfo.processInfo.systemUptime)
        suppressedMouseButtons.removeAll()
    }

    private func releasePressedShortcuts(eventTime: TimeInterval) {
        for action in Array(shortcuts.keys) {
            guard var state = shortcuts[action] else { continue }
            let shouldDispatchUp = state.isDown && !state.requiresStandaloneRelease
            state.isDown = false
            state.pressedAt = nil
            state.isInterrupted = false
            state.requiresStandaloneRelease = false
            shortcuts[action] = state
            if shouldDispatchUp {
                dispatchShortcutUp(for: action, eventTime: eventTime)
            }
        }
        pressedKeyCodes.removeAll()
    }

    private func handleEvent(
        kind: EventKind,
        inputCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        eventTime: TimeInterval
    ) -> Bool {
        var shouldSuppress: Bool
        switch kind {
        case .mouseDragged:
            shouldSuppress = suppressedMouseButtons.contains(inputCode)
        case .mouseUp:
            shouldSuppress = suppressedMouseButtons.remove(inputCode) != nil
        case .keyDown, .keyUp, .flagsChanged, .mouseDown:
            shouldSuppress = false
        }

        updatePressedKeyCodes(kind: kind, inputCode: inputCode)
        invalidateStandaloneModifierCandidateForKeyboardEvent(
            kind: kind,
            inputCode: inputCode,
            modifierFlags: modifierFlags
        )

        if kind == .keyDown {
            handleShortcutInterruptions(keyCode: inputCode, eventTime: eventTime)
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
                    keyCode: inputCode,
                    modifierFlags: modifierFlags,
                    eventTime: eventTime
                )
                continue
            }

            let transition: ShortcutTransition
            switch state.shortcut.kind {
            case .key:
                transition = transitionForKeyShortcut(
                    state.shortcut,
                    isDown: state.isDown,
                    kind: kind,
                    keyCode: inputCode,
                    modifierFlags: modifierFlags
                )
            case .mouseButton:
                transition = transitionForMouseShortcut(
                    state.shortcut,
                    isDown: state.isDown,
                    kind: kind,
                    buttonNumber: inputCode,
                    modifierFlags: modifierFlags
                )
            case .modifierOnly:
                transition = .none
            }

            switch transition {
            case .none:
                if kind == .keyDown, state.shortcut.kind == .key, inputCode == state.shortcut.keyCode {
                    let actualFlags = Shortcut.normalizedModifierFlags(modifierFlags, forKeyCode: inputCode)
                    ShortcutDiagnostics.notice(
                        "event-near-miss owner=\(ownerLabel) id=\(monitorID) action=\(action.storageName) kind=keyDown reason=modifier-mismatch keyCode=\(inputCode) actualModifiers=0x\(String(actualFlags.rawValue, radix: 16)) expected=\(state.shortcut.diagnosticDescription)"
                    )
                } else if kind == .mouseDown, state.shortcut.kind == .mouseButton, inputCode == state.shortcut.keyCode {
                    let actualFlags = Shortcut.normalizedModifierFlags(modifierFlags, forKeyCode: nil)
                    ShortcutDiagnostics.notice(
                        "event-near-miss owner=\(ownerLabel) id=\(monitorID) action=\(action.storageName) kind=mouseDown reason=modifier-mismatch buttonNumber=\(inputCode) actualModifiers=0x\(String(actualFlags.rawValue, radix: 16)) expected=\(state.shortcut.diagnosticDescription)"
                    )
                }
                break
            case .suppress:
                if kind != .flagsChanged {
                    shouldSuppress = true
                }
                ShortcutDiagnostics.notice(
                    "event-suppress-transition owner=\(ownerLabel) id=\(monitorID) action=\(action.storageName) kind=\(kind) suppressed=\(kind != .flagsChanged) reason=already-down-or-flags-held"
                )
            case .keyDown:
                state.isDown = true
                state.pressedAt = eventTime
                state.isInterrupted = false
                shortcuts[action] = state
                if state.shortcut.kind == .mouseButton {
                    suppressedMouseButtons.insert(inputCode)
                }
                shouldSuppress = true
                dispatchShortcutDown(for: action, eventTime: eventTime)
            case .keyUp:
                state.isDown = false
                state.pressedAt = nil
                state.isInterrupted = false
                shortcuts[action] = state
                if kind != .flagsChanged {
                    shouldSuppress = true
                }
                dispatchShortcutUp(for: action, eventTime: eventTime)
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
        case .mouseDown, .mouseDragged, .mouseUp:
            return .none
        }
    }

    private func transitionForMouseShortcut(
        _ shortcut: Shortcut,
        isDown: Bool,
        kind: EventKind,
        buttonNumber: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) -> ShortcutTransition {
        switch kind {
        case .mouseDown:
            guard shortcut.matchesMouseEvent(
                buttonNumber: buttonNumber,
                modifierFlags: modifierFlags
            ) else {
                return .none
            }

            return isDown ? .suppress : .keyDown
        case .mouseUp:
            return isDown && buttonNumber == shortcut.keyCode ? .keyUp : .none
        case .flagsChanged:
            guard isDown else {
                return .none
            }

            let currentFlags = Shortcut.normalizedModifierFlags(modifierFlags, forKeyCode: nil)
            return currentFlags.isSuperset(of: shortcut.modifierFlags) ? .suppress : .keyUp
        case .keyDown, .keyUp, .mouseDragged:
            return .none
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
                let shouldTrigger =
                    state.requiresStandaloneRelease
                    && !state.isInterrupted
                let shouldDispatchUp = !state.requiresStandaloneRelease
                let pressedAt = state.pressedAt
                state.isDown = false
                state.pressedAt = nil
                state.isInterrupted = false
                state.requiresStandaloneRelease = false
                shortcuts[action] = state
                ShortcutDiagnostics.notice(
                    "modifier-transition owner=\(ownerLabel) id=\(monitorID) action=\(action.storageName) transition=keyUp eventKeyCode=\(keyCode) standaloneTriggered=\(shouldTrigger) dispatchUp=\(shouldDispatchUp) expected=\(state.shortcut.diagnosticDescription)"
                )
                if shouldTrigger, let pressedAt {
                    dispatchShortcutDown(for: action, eventTime: pressedAt)
                    dispatchShortcutUp(for: action, eventTime: eventTime)
                } else if shouldDispatchUp {
                    dispatchShortcutUp(for: action, eventTime: eventTime)
                }
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
            state.requiresStandaloneRelease = standaloneModifierActions.contains(action)
            state.isInterrupted = state.requiresStandaloneRelease && !pressedKeyCodes.isEmpty
            shortcuts[action] = state
            ShortcutDiagnostics.notice(
                "modifier-transition owner=\(ownerLabel) id=\(monitorID) action=\(action.storageName) transition=keyDown eventKeyCode=\(keyCode) requiresStandaloneRelease=\(state.requiresStandaloneRelease) interrupted=\(state.isInterrupted) expected=\(state.shortcut.diagnosticDescription)"
            )
            if !state.requiresStandaloneRelease {
                dispatchShortcutDown(for: action, eventTime: eventTime)
            }
        } else if keyCode == state.shortcut.keyCode {
            let actualFlags = Shortcut.normalizedModifierFlags(modifierFlags, forKeyCode: keyCode)
            ShortcutDiagnostics.notice(
                "modifier-near-miss owner=\(ownerLabel) id=\(monitorID) action=\(action.storageName) state=up reason=flags-mismatch eventKeyCode=\(keyCode) actualModifiers=0x\(String(actualFlags.rawValue, radix: 16)) expected=\(state.shortcut.diagnosticDescription)"
            )
        }
    }

    private func updatePressedKeyCodes(kind: EventKind, inputCode: UInt16) {
        switch kind {
        case .keyDown:
            pressedKeyCodes.insert(inputCode)
        case .keyUp:
            pressedKeyCodes.remove(inputCode)
        case .flagsChanged, .mouseDown, .mouseDragged, .mouseUp:
            break
        }
    }

    private func invalidateStandaloneModifierCandidateForKeyboardEvent(
        kind: EventKind,
        inputCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) {
        guard kind == .keyDown || kind == .keyUp || kind == .flagsChanged else {
            return
        }

        for action in Array(shortcuts.keys) {
            guard var state = shortcuts[action],
                state.isDown,
                state.requiresStandaloneRelease,
                !state.isInterrupted
            else {
                continue
            }

            let isReleaseEvent = kind == .flagsChanged
                && state.shortcut.shouldReleaseModifierEvent(
                    keyCode: inputCode,
                    modifierFlags: modifierFlags
                )
            if !isReleaseEvent {
                state.isInterrupted = true
                shortcuts[action] = state
            }
        }
    }

    private func handleShortcutInterruptions(keyCode: UInt16, eventTime: TimeInterval) {
        guard !Shortcut.isModifierKeyCode(keyCode) else {
            return
        }

        for action in standaloneModifierActions {
            guard shortcuts[action]?.shortcut.isModifierOnly == true else { continue }
            onStandaloneModifierChord?(action)
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

    private func dispatchShortcutDown(for action: ShortcutAction, eventTime: TimeInterval) {
        lastMatchedEventUptime = eventTime
        ShortcutDiagnostics.recordMatch(owner: ownerLabel)
        ShortcutDiagnostics.notice(
            "event-match owner=\(ownerLabel) id=\(monitorID) action=\(action.storageName) transition=keyDown eventUptime=\(eventTime)"
        )
        DispatchQueue.main.async { [onShortcutDown] in
            guard let onShortcutDown else {
                ShortcutDiagnostics.error(
                    "event-dispatch owner=\(self.ownerLabel) id=\(self.monitorID) action=\(action.storageName) transition=keyDown result=dropped-missing-callback"
                )
                return
            }
            ShortcutDiagnostics.notice(
                "event-dispatch owner=\(self.ownerLabel) id=\(self.monitorID) action=\(action.storageName) transition=keyDown result=callback-invoked queueDelaySeconds=\(ProcessInfo.processInfo.systemUptime - eventTime)"
            )
            onShortcutDown(action, eventTime)
        }
    }

    private func dispatchShortcutUp(for action: ShortcutAction, eventTime: TimeInterval) {
        lastMatchedEventUptime = eventTime
        ShortcutDiagnostics.recordMatch(owner: ownerLabel)
        ShortcutDiagnostics.notice(
            "event-match owner=\(ownerLabel) id=\(monitorID) action=\(action.storageName) transition=keyUp eventUptime=\(eventTime)"
        )
        DispatchQueue.main.async { [onShortcutUp] in
            guard let onShortcutUp else {
                ShortcutDiagnostics.error(
                    "event-dispatch owner=\(self.ownerLabel) id=\(self.monitorID) action=\(action.storageName) transition=keyUp result=dropped-missing-callback"
                )
                return
            }
            ShortcutDiagnostics.notice(
                "event-dispatch owner=\(self.ownerLabel) id=\(self.monitorID) action=\(action.storageName) transition=keyUp result=callback-invoked queueDelaySeconds=\(ProcessInfo.processInfo.systemUptime - eventTime)"
            )
            onShortcutUp(action, eventTime)
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
        CGEventType.otherMouseDown,
        CGEventType.otherMouseDragged,
        CGEventType.otherMouseUp,
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
                ShortcutDiagnostics.recordTapState(owner: self.ownerLabel, enabled: isEnabled)
                guard !isEnabled else {
                    continue
                }

                let currentUptime = ProcessInfo.processInfo.systemUptime
                let lastEventAge = self.lastEventUptime.map { currentUptime - $0 }
                let lastMatchAge = self.lastMatchedEventUptime.map { currentUptime - $0 }
                let eventActivity = ShortcutDiagnostics.eventActivitySummary(owner: self.ownerLabel)
                ShortcutDiagnostics.error(
                    "tap-watchdog owner=\(self.ownerLabel) id=\(self.monitorID) result=disabled shortcutCount=\(self.shortcuts.count) pressedActions=\(self.pressedActionSummary) lastEventAgeSeconds=\(lastEventAge.map { String($0) } ?? "never") lastMatchAgeSeconds=\(lastMatchAge.map { String($0) } ?? "never") eventTypes={\(eventActivity)}"
                )
                ShortcutDiagnostics.logEnvironment(reason: "tap-watchdog-disabled.\(self.ownerLabel)")
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
        case .otherMouseDown:
            self = .mouseDown
        case .otherMouseDragged:
            self = .mouseDragged
        case .otherMouseUp:
            self = .mouseUp
        default:
            return nil
        }
    }
}
