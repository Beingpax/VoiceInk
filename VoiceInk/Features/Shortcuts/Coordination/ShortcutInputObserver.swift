import AppKit
import CoreGraphics
import Foundation

/// Logs shortcut candidates delivered to a passive tap.
@MainActor
final class ShortcutInputObserver {
    typealias TapFactory = ShortcutMonitor.EventTapFactory

    private let worker: ShortcutInputObserverWorker
    private let tapThread = ShortcutEventTapThread.shared

    init(
        makeTap: @escaping TapFactory = {
            try SystemShortcutEventTap(eventsOfInterest: $0, options: .listenOnly, handler: $1)
        },
        allowsInput: @escaping @Sendable () -> Bool = { UserSessionInputPolicy.allowsShortcutHandling }
    ) {
        UserSessionInputPolicy.startObserving()
        worker = ShortcutInputObserverWorker(makeTap: makeTap, allowsInput: allowsInput)
    }

    func start() {
        let worker = worker
        tapThread.performAndWait { worker.start() }
    }

    func stop() {
        let worker = worker
        tapThread.performAndWait { worker.stop() }
    }

    var diagnosticSummary: String {
        let worker = worker
        return tapThread.performAndWait { worker.diagnosticSummary }
    }

    isolated deinit { stop() }
}

/// Keeps diagnostic tap state on the shortcut thread.
private final class ShortcutInputObserverWorker: @unchecked Sendable {
    typealias TapFactory = ShortcutMonitor.EventTapFactory

    private let makeTap: TapFactory
    private let allowsInput: @Sendable () -> Bool
    private var tap: (any ShortcutEventTap)?
    private var timer: Timer?
    private var downs = 0
    private var ups = 0
    private var modifiers = 0
    private var mouseEvents = 0
    private var functionEvents = 0
    private var tracedEvents = 0
    private var repeats = 0
    private var installFailures = 0
    private var lastEventAt: TimeInterval?
    private var lastShortcutEventAt: TimeInterval?
    private var lastShortcutEvent = "none"
    private var trackedKeyCodes = Set<UInt16>()
    private var lastFailureLogAt: TimeInterval?
    private var lastRepeatLogAt: TimeInterval?

    init(
        makeTap: @escaping TapFactory,
        allowsInput: @escaping @Sendable () -> Bool
    ) {
        self.makeTap = makeTap
        self.allowsInput = allowsInput
    }

    func start() {
        stop()
        recover()
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            self?.recover()
        }
        timer.tolerance = 0.2
        self.timer = timer
        RunLoop.current.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        tap?.stop()
        tap = nil
        trackedKeyCodes.removeAll()
    }

    private func recover() {
        DispatchQueue.main.async { ShortcutDiagnostics.observeEnvironment(reason: "input-observer-health") }
        guard allowsInput() else { return }
        if let tap, tap.isValid {
            if tap.isEnabled { return }
            tap.enable()
            if tap.isEnabled {
                ShortcutDiagnostics.notice("input-observer result=re-enabled enabled=true")
                return
            }
            ShortcutDiagnostics.warning("input-observer result=re-enable-failed action=rebuild")
        }
        tap?.stop()
        tap = nil
        trackedKeyCodes.removeAll()
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged, .otherMouseDown, .otherMouseUp].reduce(CGEventMask(0)) {
            $0 | (CGEventMask(1) << $1.rawValue)
        }
        do {
            tap = try makeTap(mask) { [weak self] type, event in
                self?.receive(type: type, event: event)
                return false // Never consume input.
            }
            lastFailureLogAt = nil
            ShortcutDiagnostics.notice("input-observer result=installed scope=session-shortcut-candidates enabled=\(tap?.isEnabled == true)")
        } catch {
            installFailures += 1
            let now = ProcessInfo.processInfo.systemUptime
            if lastFailureLogAt.map({ now - $0 >= 60 }) ?? true {
                lastFailureLogAt = now
                ShortcutDiagnostics.error("input-observer result=install-failed attempts=\(installFailures)")
            }
        }
    }

    private func receive(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            trackedKeyCodes.removeAll()
            ShortcutDiagnostics.warning("input-observer result=disabled reason=\(type == .tapDisabledByTimeout ? "timeout" : "user-input")")
            recover()
            return
        }
        guard allowsInput() else { return }
        lastEventAt = ProcessInfo.processInfo.systemUptime
        let code: UInt16
        let kind: String
        let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
        let isRepeat = type == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        switch type {
        case .keyDown, .keyUp:
            if type == .keyDown { downs += 1 } else { ups += 1 }
            code = UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode))
            let shortcut = Shortcut.key(keyCode: code, modifierFlags: flags)
            let supported = ShortcutValidator.inputShapeError(for: shortcut, action: .cancelRecorder) == nil
            if type == .keyDown {
                if supported { trackedKeyCodes.insert(code) }
                else if !isRepeat { trackedKeyCodes.remove(code) }
                guard supported || (isRepeat && trackedKeyCodes.contains(code)) else { return }
            } else {
                // Log key releases even after modifiers are released.
                let wasTracked = trackedKeyCodes.remove(code) != nil
                guard supported || wasTracked else { return }
            }
            if Shortcut.isFunctionKeyCode(code) { functionEvents += 1 }
            kind = "key"
        case .flagsChanged:
            modifiers += 1
            code = UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode))
            guard Shortcut.isModifierKeyCode(code) else { return }
            kind = "modifier"
        case .otherMouseDown, .otherMouseUp:
            mouseEvents += 1
            code = UInt16(clamping: event.getIntegerValueField(.mouseEventButtonNumber))
            guard Shortcut.isSupportedMouseButtonNumber(code) else { return }
            kind = "mouse"
        default: return
        }
        tracedEvents += 1
        lastShortcutEventAt = ProcessInfo.processInfo.systemUptime
        let phase = type == .flagsChanged ? "flags" : (type == .keyDown || type == .otherMouseDown) ? "down" : "up"
        lastShortcutEvent = "kind=\(kind),code=\(code),phase=\(phase),repeat=\(isRepeat)"
        if isRepeat {
            repeats += 1
            let now = ProcessInfo.processInfo.systemUptime
            guard lastRepeatLogAt.map({ now - $0 >= 5 }) ?? true else { return }
            lastRepeatLogAt = now
        }
        ShortcutDiagnostics.notice("input-observer kind=\(kind) event=\(phase) code=\(code) flags=0x\(String(event.flags.rawValue, radix: 16)) repeat=\(isRepeat) timestamp=\(event.timestamp) sourcePID=\(event.getIntegerValueField(.eventSourceUnixProcessID)) capture=\(ShortcutDiagnostics.captureSummary)")
    }

    var diagnosticSummary: String {
        let age = lastEventAt.map { String(format: "%.1f", max(0, ProcessInfo.processInfo.systemUptime - $0)) } ?? "never"
        let shortcutAge = lastShortcutEventAt.map { String(format: "%.1f", max(0, ProcessInfo.processInfo.systemUptime - $0)) } ?? "never"
        return "valid=\(tap?.isValid == true) enabled=\(tap?.isEnabled == true) timerActive=\(timer != nil) installFailures=\(installFailures) events={down:\(downs),up:\(ups),modifiers:\(modifiers),mouse:\(mouseEvents)} functionEvents=\(functionEvents) tracedEvents=\(tracedEvents) repeats=\(repeats) lastEventAge=\(age) lastShortcutEventAge=\(shortcutAge) lastShortcutEvent={\(lastShortcutEvent)}"
    }
}
