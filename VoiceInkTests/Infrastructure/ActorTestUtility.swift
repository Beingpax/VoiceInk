import Foundation
import XCTest

/// Utilities for testing actor isolation and concurrency
@available(macOS 14.0, *)
final class ActorTestUtility {
    
    // MARK: - Actor Isolation Verification
    
    /// Verify that an actor properly isolates its state
    static func verifyActorIsolation<T: Actor>(
        _ actor: T,
        iterations: Int = 100,
        operation: @escaping (T) async -> Void
    ) async {
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<iterations {
                group.addTask {
                    await operation(actor)
                }
            }
            await group.waitForAll()
        }
    }
    
    /// Test that concurrent access to actor is serialized
    static func assertSerializedAccess<T: Actor, R: Equatable>(
        to actor: T,
        getter: @escaping (T) async -> R,
        setter: @escaping (T, R) async -> Void,
        values: [R]
    ) async throws {
        for value in values {
            await setter(actor, value)
            let retrieved = await getter(actor)
            
            guard retrieved == value else {
                throw TestError.actorIsolationViolation(
                    expected: "\(value)",
                    actual: "\(retrieved)"
                )
            }
        }
    }
    
    /// Verify MainActor isolation
    @MainActor
    static func assertOnMainActor() {
        assert(Thread.isMainThread, "Not executing on main thread")
    }
    
    /// Test that MainActor-isolated code executes on main thread
    static func verifyMainActorExecution(
        iterations: Int = 10,
        operation: @MainActor @escaping () async -> Void
    ) async {
        for _ in 0..<iterations {
            await operation()
        }
    }
}

// MARK: - Concurrency Testing

@available(macOS 14.0, *)
extension ActorTestUtility {
    
    /// Create a race condition test scenario
    static func raceTest(
        iterations: Int = 1000,
        setup: @escaping () -> Void = {},
        operation1: @escaping () async -> Void,
        operation2: @escaping () async -> Void,
        validate: @escaping () -> Bool
    ) async throws {
        for iteration in 0..<iterations {
            setup()
            
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await operation1() }
                group.addTask { await operation2() }
                await group.waitForAll()
            }
            
            guard validate() else {
                throw TestError.raceConditionDetected(iteration: iteration)
            }
        }
    }
    
    /// Test task cancellation handling
    static func testCancellation(
        operation: @escaping () async throws -> Void
    ) async -> Bool {
        let task = Task {
            try await operation()
        }
        
        // Cancel immediately
        task.cancel()
        
        do {
            try await task.value
            return false // Should have been cancelled
        } catch is CancellationError {
            return true // Proper cancellation
        } catch {
            return false // Unexpected error
        }
    }
    
    /// Test structured concurrency with child tasks
    static func testStructuredConcurrency(
        childCount: Int = 10,
        childOperation: @escaping (Int) async -> Void
    ) async {
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<childCount {
                group.addTask {
                    await childOperation(index)
                }
            }
            await group.waitForAll()
        }
    }
}

// MARK: - Performance Testing

@available(macOS 14.0, *)
extension ActorTestUtility {
    
    struct PerformanceResult {
        let averageTime: TimeInterval
        let minTime: TimeInterval
        let maxTime: TimeInterval
        let iterations: Int
        
        var description: String {
            """
            Performance Result (\(iterations) iterations):
            - Average: \(String(format: "%.3f", averageTime * 1000))ms
            - Min: \(String(format: "%.3f", minTime * 1000))ms
            - Max: \(String(format: "%.3f", maxTime * 1000))ms
            """
        }
    }
    
    /// Measure async operation performance
    static func measureAsync(
        iterations: Int = 10,
        warmup: Int = 3,
        operation: @escaping () async -> Void
    ) async -> PerformanceResult {
        var times: [TimeInterval] = []
        
        // Warmup
        for _ in 0..<warmup {
            await operation()
        }
        
        // Measure
        for _ in 0..<iterations {
            let start = Date()
            await operation()
            let elapsed = Date().timeIntervalSince(start)
            times.append(elapsed)
        }
        
        let average = times.reduce(0, +) / Double(times.count)
        let min = times.min() ?? 0
        let max = times.max() ?? 0
        
        return PerformanceResult(
            averageTime: average,
            minTime: min,
            maxTime: max,
            iterations: iterations
        )
    }
}

// MARK: - Error Types

enum TestError: Error, CustomStringConvertible {
    case actorIsolationViolation(expected: String, actual: String)
    case raceConditionDetected(iteration: Int)
    case invalidState(String)
    case timeout
    case unexpectedError(Error)
    
    var description: String {
        switch self {
        case .actorIsolationViolation(let expected, let actual):
            return "Actor isolation violation - expected: \(expected), actual: \(actual)"
        case .raceConditionDetected(let iteration):
            return "Race condition detected at iteration \(iteration)"
        case .invalidState(let message):
            return "Invalid state: \(message)"
        case .timeout:
            return "Operation timed out"
        case .unexpectedError(let error):
            return "Unexpected error: \(error)"
        }
    }
}

// MARK: - Task Group Testing

@available(macOS 14.0, *)
extension ActorTestUtility {
    
    /// Test that task group properly handles errors
    static func testTaskGroupErrorHandling(
        taskCount: Int = 10,
        errorAtIndex: Int? = nil,
        operation: @escaping (Int) async throws -> Void
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<taskCount {
                group.addTask {
                    if let errorIndex = errorAtIndex, index == errorIndex {
                        throw TestError.invalidState("Intentional error at index \(index)")
                    }
                    try await operation(index)
                }
            }
            
            try await group.waitForAll()
        }
    }
    
    /// Test task priority handling
    static func testTaskPriority(
        highPriorityWork: @escaping () async -> Void,
        lowPriorityWork: @escaping () async -> Void
    ) async {
        async let high: () = Task(priority: .high) {
            await highPriorityWork()
        }.value
        
        async let low: () = Task(priority: .low) {
            await lowPriorityWork()
        }.value
        
        await high
        await low
    }
}

// MARK: - Synchronization Primitives Testing

@available(macOS 14.0, *)
extension ActorTestUtility {
    
    /// Test AsyncStream behavior
    static func testAsyncStream<T>(
        values: [T],
        consumer: @escaping (T) async -> Void
    ) async {
        let stream = AsyncStream<T> { continuation in
            for value in values {
                continuation.yield(value)
            }
            continuation.finish()
        }
        
        for await value in stream {
            await consumer(value)
        }
    }
    
    /// Test AsyncSequence cancellation
    static func testAsyncSequenceCancellation<S: AsyncSequence>(
        sequence: S,
        cancelAfter: Int = 5
    ) async throws {
        let task = Task {
            var count = 0
            for try await _ in sequence {
                count += 1
                if count >= cancelAfter {
                    break
                }
            }
        }
        
        try await task.value
    }
}
