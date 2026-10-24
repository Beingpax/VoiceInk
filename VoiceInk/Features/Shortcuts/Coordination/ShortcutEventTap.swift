import CoreGraphics
import Foundation

protocol ShortcutEventTap: AnyObject {
    var isValid: Bool { get }
    var isEnabled: Bool { get }
    func enable()
    func stop()
}

enum ShortcutEventTapError: Error {
    case creationFailed
    case runLoopSourceFailed
    case enableFailed
}

/// Owns a system tap on the shortcut thread.
final class SystemShortcutEventTap: ShortcutEventTap {
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private let handler: (CGEventType, CGEvent) -> Bool
    private let runLoop: CFRunLoop

    init(eventsOfInterest: CGEventMask, options: CGEventTapOptions = .defaultTap, handler: @escaping (CGEventType, CGEvent) -> Bool) throws {
        precondition(ShortcutEventTapThread.shared.isCurrent)
        self.handler = handler
        self.runLoop = CFRunLoopGetCurrent()
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            autoreleasepool { () -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<SystemShortcutEventTap>.fromOpaque(userInfo).takeUnretainedValue()
                return tap.handler(type, event) ? nil : Unmanaged.passUnretained(event)
            }
        }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: options,
            eventsOfInterest: eventsOfInterest,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw ShortcutEventTapError.creationFailed
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            throw ShortcutEventTapError.runLoopSourceFailed
        }
        self.port = port
        self.source = source
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        guard CGEvent.tapIsEnabled(tap: port) else {
            stop()
            throw ShortcutEventTapError.enableFailed
        }
    }

    var isValid: Bool {
        guard let port, let source else { return false }
        return CFMachPortIsValid(port) && CFRunLoopSourceIsValid(source)
    }

    var isEnabled: Bool {
        guard isValid, let port else { return false }
        return CGEvent.tapIsEnabled(tap: port)
    }

    func enable() {
        guard isValid, let port else { return }
        CGEvent.tapEnable(tap: port, enable: true)
    }

    func stop() {
        if let source {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFRunLoopSourceInvalidate(source)
            self.source = nil
        }
        if let port {
            CFMachPortInvalidate(port)
            self.port = nil
        }
    }

    deinit {
        stop()
    }
}
