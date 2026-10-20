import CoreFoundation
import Foundation

/// Runs shortcut matching independently of the main thread.
final class ShortcutEventTapThread: @unchecked Sendable {
    static let shared = ShortcutEventTapThread()

    private final class ResultBox<Value>: @unchecked Sendable {
        var value: Value?
    }

    private let thread: Thread
    private let runLoop: CFRunLoop

    private init() {
        let ready = DispatchSemaphore(value: 0)
        let startup = ResultBox<CFRunLoop>()
        let thread = Thread {
            let keepAlive = NSMachPort()
            RunLoop.current.add(keepAlive, forMode: .common)
            startup.value = CFRunLoopGetCurrent()
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "com.prakashjoshipax.voiceink.shortcut-event-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        self.thread = thread
        self.runLoop = startup.value!
    }

    var isCurrent: Bool { Thread.current === thread }

    func perform(_ body: @escaping () -> Void) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
            autoreleasepool { body() }
        }
        CFRunLoopWakeUp(runLoop)
    }

    /// Waits for configuration or teardown; tap callbacks never wait for main.
    func performAndWait<Value>(_ body: @escaping () -> Value) -> Value {
        if isCurrent { return body() }
        let completed = DispatchSemaphore(value: 0)
        let result = ResultBox<Value>()
        perform {
            result.value = body()
            completed.signal()
        }
        completed.wait()
        return result.value!
    }
}
