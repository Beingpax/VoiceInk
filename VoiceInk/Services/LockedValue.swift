import Foundation

/// A small mutex-guarded box for state shared with callbacks that fire on arbitrary queues
/// (KVO observers, `URLSession` delegates, audio callbacks).
///
/// Swift 6 rejects capturing a mutable `var` in a concurrently-executing closure; this gives that
/// state a safe home without reaching for an actor, which would force the callback to be async.
final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        storedValue = value
    }

    var value: Value {
        lock.withLock { storedValue }
    }

    func set(_ newValue: Value) {
        lock.withLock { storedValue = newValue }
    }

    /// Mutates under the lock and returns whatever the body produces.
    @discardableResult
    func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.withLock { body(&storedValue) }
    }
}
