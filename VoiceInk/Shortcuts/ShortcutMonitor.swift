import AppKit
import CoreGraphics
import Foundation

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
    private let ownerLabel: String

    /// Per-owner install state for System Info / log export.
    /// Keyed by `ownerLabel` so Mode/RecorderPanel empty sets do not clobber Recording.
    private static var installSucceededByOwner: [String: Bool] = [:]
    private static var installDetailByOwner: [String: String] = [:]
    private static var registeredSummaryByOwner: [String: String] = [:]
    private static var liveTapEnabledByOwner: [String: Bool] = [:]
    private static var liveTapPortByOwner: [String: CFMachPort] = [:]

    /// Convenience snapshot used by System Info (prefers Recording owner).
    static var lastInstallSucceeded: Bool? {
        installSucceededByOwner["Recording"] ?? installSucceededByOwner.values.first
    }

    static var lastInstallDetail: String {
        if let detail = installDetailByOwner["Recording"] {
            return detail
        }
        let parts = installDetailByOwner.map { "\($0.key): \($0.value)" }.sorted()
        return parts.isEmpty ? "not-started" : parts.joined(separator: " | ")
    }

    static var lastRegisteredShortcutSummary: String {
        if let summary = registeredSummaryByOwner["Recording"] {
            return summary
        }
        let parts = registeredSummaryByOwner.map { "\($0.key): \($0.value)" }.sorted()
        return parts.isEmpty ? "none" : parts.joined(separator: " | ")
    }

    static var allOwnersInstallSummary: String {
        let owners = Set(installDetailByOwner.keys).union(registeredSummaryByOwner.keys).sorted()
        guard !owners.isEmpty else {
            return "not-started"
        }

        return owners.map { owner in
            let success = installSucceededByOwner[owner].map { $0 ? "ok" : "fail" } ?? "?"
            let detail = installDetailByOwner[owner] ?? "n/a"
            let summary = registeredSummaryByOwner[owner] ?? "none"
            return "[\(owner)] \(success) \(detail) shortcuts={\(summary)}"
        }.joined(separator: " || ")
    }

    static var allOwnersLiveTapSummary: String {
        let owners = Set(liveTapEnabledByOwner.keys).union(liveTapPortByOwner.keys).sorted()
        guard !owners.isEmpty else {
            return "no-live-taps"
        }

        return owners.map { owner in
            let enabled: String
            if let port = liveTapPortByOwner[owner] {
                enabled = CGEvent.tapIsEnabled(tap: port) ? "enabled" : "DISABLED"
            } else if let cached = liveTapEnabledByOwner[owner] {
                enabled = cached ? "enabled(cached)" : "DISABLED(cached)"
            } else {
                enabled = "unknown"
            }
            return "[\(owner)] \(enabled)"
        }.joined(separator: " || ")
    }

    static func installSucceededByOwnerValue(for owner: String) -> Bool? {
        installSucceededByOwner[owner]
    }

    private static let shortcutInterruptionWindow: TimeInterval = 1.0

    init(ownerLabel: String = "ShortcutMonitor") {
        self.ownerLabel = ownerLabel
    }

    deinit {
        stop()
    }

    @discardableResult
    func start(
        shortcuts: [ShortcutAction: Shortcut],
        interruptibleActions: Set<ShortcutAction> = [],
        onKeyDown: @escaping (ShortcutAction, TimeInterval) -> Void,
        onKeyUp: @escaping (ShortcutAction, TimeInterval) -> Void,
        onShortcutInterrupted: ((ShortcutAction, TimeInterval) -> Void)? = nil
    ) -> Bool {
        stop()

        for (action, shortcut) in shortcuts {
            self.shortcuts[action] = ShortcutState(shortcut: shortcut)
        }

        let summary = Self.summarize(shortcuts: shortcuts)
        Self.registeredSummaryByOwner[ownerLabel] = summary

        let permissions = ShortcutDiagnostics.permissionSnapshot()
        ShortcutDiagnostics.notice(
            "[\(ownerLabel)] start requested: count=\(shortcuts.count) interruptible=\(interruptibleActions.count) shortcuts=\(summary) \(permissions.fingerprint)"
        )

        guard !self.shortcuts.isEmpty else {
            ShortcutDiagnostics.notice("[\(ownerLabel)] start skipped: no shortcuts registered")
            Self.installSucceededByOwner[ownerLabel] = true
            Self.installDetailByOwner[ownerLabel] = "empty-shortcut-set"
            Self.liveTapEnabledByOwner[ownerLabel] = false
            Self.liveTapPortByOwner.removeValue(forKey: ownerLabel)
            return true
        }

        self.interruptibleActions = interruptibleActions
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        self.onShortcutInterrupted = onShortcutInterrupted

        return installEventTap()
    }

    func stop() {
        let hadTap = eventTap != nil
        let previousCount = shortcuts.count
        let wasEnabled =
            eventTap.map { CGEvent.tapIsEnabled(tap: $0) }

        if let eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
            self.eventTapRunLoopSource = nil
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }

        Self.liveTapPortByOwner.removeValue(forKey: ownerLabel)
        Self.liveTapEnabledByOwner[ownerLabel] = false

        if hadTap || previousCount > 0 {
            ShortcutDiagnostics.notice(
                "[\(ownerLabel)] stop: hadTap=\(hadTap) wasEnabled=\(wasEnabled.map(String.init(describing:)) ?? "n/a") previousCount=\(previousCount)"
            )
        }

        shortcuts = [:]
        interruptibleActions = []
        onKeyDown = nil
        onKeyUp = nil
        onShortcutInterrupted = nil
    }

    private func installEventTap() -> Bool {
        let permissions = ShortcutDiagnostics.logPermissionSnapshot(
            reason: "\(ownerLabel).installEventTap",
            force: true
        )

        if !permissions.accessibilityTrusted {
            ShortcutDiagnostics.error(
                "[\(ownerLabel)] Accessibility not trusted — CGEvent.tapCreate(.defaultTap) will fail or be inert. Open System Settings → Privacy & Security → Accessibility."
            )
        }
        if permissions.secureEventInputEnabled {
            ShortcutDiagnostics.error(
                "[\(ownerLabel)] Secure Event Input is enabled (e.g. password field). Global key events may be blocked until it turns off."
            )
        }
        if !permissions.listenEventAccess {
            ShortcutDiagnostics.notice(
                "[\(ownerLabel)] Listen Event Access (Input Monitoring) is false. defaultTap primarily needs Accessibility, but some macOS versions also gate listening."
            )
        }

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let monitor = Unmanaged<ShortcutMonitor>.fromOpaque(userInfo).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                let disableReason =
                    type == .tapDisabledByTimeout ? "tapDisabledByTimeout" : "tapDisabledByUserInput"
                let perms = ShortcutDiagnostics.permissionSnapshot()
                ShortcutDiagnostics.error(
                    "[\(monitor.ownerLabel)] EVENT TAP DISABLED reason=\(disableReason) \(perms.fingerprint) secureInput=\(perms.secureEventInputEnabled) — re-enabling and resetting pressed state"
                )
                ShortcutMonitor.liveTapEnabledByOwner[monitor.ownerLabel] = false

                monitor.resetPressedShortcutsAfterTapInterruption()
                if let eventTap = monitor.eventTap {
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                    let reenabled = CGEvent.tapIsEnabled(tap: eventTap)
                    ShortcutMonitor.liveTapEnabledByOwner[monitor.ownerLabel] = reenabled
                    if reenabled {
                        ShortcutDiagnostics.notice(
                            "[\(monitor.ownerLabel)] event tap re-enabled successfully after \(disableReason)"
                        )
                    } else {
                        ShortcutDiagnostics.error(
                            "[\(monitor.ownerLabel)] event tap RE-ENABLE FAILED after \(disableReason) — shortcuts dead until restart/refresh. \(perms.humanSummary)"
                        )
                    }
                } else {
                    ShortcutDiagnostics.error(
                        "[\(monitor.ownerLabel)] event tap disabled but port is nil — cannot re-enable"
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
            let detail =
                "tapCreate-failed \(permissions.fingerprint) implication=\(permissions.humanSummary)"
            Self.installSucceededByOwner[ownerLabel] = false
            Self.installDetailByOwner[ownerLabel] = detail
            Self.liveTapEnabledByOwner[ownerLabel] = false
            Self.liveTapPortByOwner.removeValue(forKey: ownerLabel)
            ShortcutDiagnostics.error(
                "[\(ownerLabel)] Failed to install global shortcut event tap. \(detail)"
            )
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            CFMachPortInvalidate(eventTap)
            let detail = "runLoopSource-failed \(permissions.fingerprint)"
            Self.installSucceededByOwner[ownerLabel] = false
            Self.installDetailByOwner[ownerLabel] = detail
            Self.liveTapEnabledByOwner[ownerLabel] = false
            Self.liveTapPortByOwner.removeValue(forKey: ownerLabel)
            ShortcutDiagnostics.error(
                "[\(ownerLabel)] Failed to create global shortcut event tap run loop source"
            )
            return false
        }

        self.eventTap = eventTap
        eventTapRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        let isEnabled = CGEvent.tapIsEnabled(tap: eventTap)
        Self.liveTapPortByOwner[ownerLabel] = eventTap
        Self.liveTapEnabledByOwner[ownerLabel] = isEnabled

        let detail =
            "installed enabled=\(isEnabled) count=\(shortcuts.count) \(permissions.fingerprint)"
        Self.installSucceededByOwner[ownerLabel] = isEnabled
        Self.installDetailByOwner[ownerLabel] = detail

        if isEnabled {
            ShortcutDiagnostics.notice(
                "[\(ownerLabel)] Global shortcut event tap installed. \(detail)"
            )
        } else {
            ShortcutDiagnostics.error(
                "[\(ownerLabel)] Event tap created but NOT ENABLED after tapEnable. \(detail) \(permissions.humanSummary)"
            )
        }
        return isEnabled
    }

    private func handleCGEvent(type: CGEventType, event: CGEvent) -> Bool {
        guard let eventKind = EventKind(type) else {
            return false
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let rawFlags = event.flags.rawValue
        let modifierFlags = NSEvent.ModifierFlags(rawValue: UInt(rawFlags))
        return handleEvent(
            kind: eventKind,
            keyCode: keyCode,
            modifierFlags: modifierFlags,
            rawFlags: rawFlags,
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

        ShortcutDiagnostics.notice(
            "[\(ownerLabel)] resetting \(pressedActions.count) pressed shortcut(s) after tap interruption: \(pressedActions.map(\.displayName).joined(separator: ", "))"
        )

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
        rawFlags: UInt64,
        eventTime: TimeInterval
    ) -> Bool {
        var shouldSuppress = false
        var suppressReasons: [String] = []
        let normalizedFlags = Shortcut.normalizedModifierFlags(modifierFlags, forKeyCode: keyCode)

        if kind == .keyDown {
            handleShortcutInterruptions(keyCode: keyCode, eventTime: eventTime)
        }

        for action in Array(shortcuts.keys) {
            guard var state = shortcuts[action] else {
                continue
            }

            if state.shortcut.isModifierOnly {
                let modifierOutcome = handleModifierOnlyShortcut(
                    action: action,
                    state: state,
                    kind: kind,
                    keyCode: keyCode,
                    modifierFlags: modifierFlags,
                    rawFlags: rawFlags,
                    eventTime: eventTime
                )
                // Modifier-only path historically does not suppress the event; log that clearly.
                if modifierOutcome != .none {
                    ShortcutDiagnostics.notice(
                        "[\(ownerLabel)] modifier-only outcome=\(modifierOutcome) action=\(action.displayName) willSuppressEvent=false (modifier-only never swallows flagsChanged)"
                    )
                }
                continue
            }

            let transition = transitionForKeyShortcut(
                state.shortcut,
                isDown: state.isDown,
                kind: kind,
                keyCode: keyCode,
                modifierFlags: modifierFlags
            )

            // Always log when the pressed key is one we care about (match or near-miss).
            if shouldLogKeyShortcutEvent(
                shortcut: state.shortcut,
                kind: kind,
                keyCode: keyCode,
                transition: transition
            ) {
                ShortcutDiagnostics.notice(
                    "[\(ownerLabel)] key-event action=\(action.displayName) kind=\(kind) keyCode=\(keyCode) rawFlags=0x\(String(rawFlags, radix: 16)) normalizedFlags=0x\(String(normalizedFlags.rawValue, radix: 16)) isDown=\(state.isDown) transition=\(transition) expected=\(state.shortcut.diagnosticDescription)"
                )
            }

            switch transition {
            case .none:
                break
            case .suppress:
                shouldSuppress = true
                suppressReasons.append("\(action.displayName):suppress(already-down-or-flags)")
            case .keyDown:
                state.isDown = true
                state.pressedAt = eventTime
                state.isInterrupted = false
                shortcuts[action] = state
                shouldSuppress = true
                suppressReasons.append("\(action.displayName):keyDown")
                dispatchKeyDown(for: action, eventTime: eventTime)
            case .keyUp:
                state.isDown = false
                state.pressedAt = nil
                state.isInterrupted = false
                shortcuts[action] = state
                shouldSuppress = true
                suppressReasons.append("\(action.displayName):keyUp")
                dispatchKeyUp(for: action, eventTime: eventTime)
            }
        }

        if shouldSuppress {
            ShortcutDiagnostics.notice(
                "[\(ownerLabel)] SUPPRESS event kind=\(kind) keyCode=\(keyCode) rawFlags=0x\(String(rawFlags, radix: 16)) reasons=[\(suppressReasons.joined(separator: ", "))] (returning nil from event tap — system/app will not receive this key)"
            )
        }

        return shouldSuppress
    }

    private enum ShortcutTransition: CustomStringConvertible {
        case none
        case suppress
        case keyDown
        case keyUp

        var description: String {
            switch self {
            case .none: return "none"
            case .suppress: return "suppress"
            case .keyDown: return "keyDown"
            case .keyUp: return "keyUp"
            }
        }
    }

    private enum ModifierOnlyOutcome: CustomStringConvertible {
        case none
        case keyDown
        case keyUp
        case nearMiss

        var description: String {
            switch self {
            case .none: return "none"
            case .keyDown: return "keyDown"
            case .keyUp: return "keyUp"
            case .nearMiss: return "nearMiss"
            }
        }
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

    @discardableResult
    private func handleModifierOnlyShortcut(
        action: ShortcutAction,
        state: ShortcutState,
        kind: EventKind,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        rawFlags: UInt64,
        eventTime: TimeInterval
    ) -> ModifierOnlyOutcome {
        var state = state

        guard kind == .flagsChanged else {
            return .none
        }

        let normalizedFlags = Shortcut.normalizedModifierFlags(modifierFlags, forKeyCode: keyCode)

        if state.isDown {
            if state.shortcut.shouldReleaseModifierEvent(keyCode: keyCode, modifierFlags: modifierFlags) {
                ShortcutDiagnostics.notice(
                    "[\(ownerLabel)] modifier-only keyUp action=\(action.displayName) keyCode=\(keyCode) rawFlags=0x\(String(rawFlags, radix: 16)) normalizedFlags=0x\(String(normalizedFlags.rawValue, radix: 16)) expected=\(state.shortcut.diagnosticDescription)"
                )
                state.isDown = false
                state.pressedAt = nil
                state.isInterrupted = false
                shortcuts[action] = state
                dispatchKeyUp(for: action, eventTime: eventTime)
                return .keyUp
            }

            return .none
        }

        if state.shortcut.matchesModifierEvent(keyCode: keyCode, modifierFlags: modifierFlags) {
            ShortcutDiagnostics.notice(
                "[\(ownerLabel)] modifier-only keyDown action=\(action.displayName) keyCode=\(keyCode) rawFlags=0x\(String(rawFlags, radix: 16)) normalizedFlags=0x\(String(normalizedFlags.rawValue, radix: 16)) expected=\(state.shortcut.diagnosticDescription)"
            )
            state.isDown = true
            state.pressedAt = eventTime
            state.isInterrupted = false
            shortcuts[action] = state
            dispatchKeyDown(for: action, eventTime: eventTime)
            return .keyDown
        }

        if shouldLogModifierNearMiss(
            shortcut: state.shortcut,
            keyCode: keyCode,
            normalizedFlags: normalizedFlags
        ) {
            ShortcutDiagnostics.notice(
                "[\(ownerLabel)] modifier-only near-miss action=\(action.displayName) keyCode=\(keyCode) rawFlags=0x\(String(rawFlags, radix: 16)) normalizedFlags=0x\(String(normalizedFlags.rawValue, radix: 16)) expected=\(state.shortcut.diagnosticDescription)"
            )
            return .nearMiss
        }

        return .none
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

            ShortcutDiagnostics.notice(
                "[\(ownerLabel)] shortcut interrupted action=\(action.displayName) extraKeyCode=\(keyCode) heldFor=\(eventTime - pressedAt)s expected=\(state.shortcut.diagnosticDescription)"
            )

            state.isInterrupted = true
            shortcuts[action] = state
            dispatchShortcutInterrupted(for: action, eventTime: eventTime)
        }
    }

    private func dispatchKeyDown(for action: ShortcutAction, eventTime: TimeInterval) {
        ShortcutDiagnostics.notice(
            "[\(ownerLabel)] dispatch keyDown action=\(action.displayName)"
        )
        DispatchQueue.main.async { [onKeyDown] in
            onKeyDown?(action, eventTime)
        }
    }

    private func dispatchKeyUp(for action: ShortcutAction, eventTime: TimeInterval) {
        ShortcutDiagnostics.notice(
            "[\(ownerLabel)] dispatch keyUp action=\(action.displayName)"
        )
        DispatchQueue.main.async { [onKeyUp] in
            onKeyUp?(action, eventTime)
        }
    }

    private func dispatchShortcutInterrupted(for action: ShortcutAction, eventTime: TimeInterval) {
        ShortcutDiagnostics.notice(
            "[\(ownerLabel)] dispatch interrupted action=\(action.displayName)"
        )
        DispatchQueue.main.async { [onShortcutInterrupted] in
            onShortcutInterrupted?(action, eventTime)
        }
    }

    /// Log when the physical key matches a registered shortcut key, or a transition occurred.
    /// Avoids flooding logs for unrelated typing.
    private func shouldLogKeyShortcutEvent(
        shortcut: Shortcut,
        kind: EventKind,
        keyCode: UInt16,
        transition: ShortcutTransition
    ) -> Bool {
        if transition != .none {
            return true
        }

        switch kind {
        case .keyDown, .keyUp:
            return keyCode == shortcut.keyCode
        case .flagsChanged:
            return false
        }
    }

    /// Log modifier-only near-misses when the user is building toward the registered chord.
    private func shouldLogModifierNearMiss(
        shortcut: Shortcut,
        keyCode: UInt16,
        normalizedFlags: NSEvent.ModifierFlags
    ) -> Bool {
        if Shortcut.isModifierKeyCode(keyCode), !normalizedFlags.isEmpty {
            return !normalizedFlags.intersection(shortcut.modifierFlags).isEmpty
        }
        return false
    }

    private static func summarize(shortcuts: [ShortcutAction: Shortcut]) -> String {
        guard !shortcuts.isEmpty else {
            return "none"
        }

        return shortcuts
            .map { "\($0.key.displayName)=\($0.value.diagnosticDescription)" }
            .sorted()
            .joined(separator: " | ")
    }

    private static let eventMask: CGEventMask = [
        CGEventType.keyDown,
        CGEventType.keyUp,
        CGEventType.flagsChanged,
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
