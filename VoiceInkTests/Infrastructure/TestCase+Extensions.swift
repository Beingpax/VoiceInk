import XCTest
@testable import VoiceInk

// MARK: - Memory Leak Detection

extension XCTestCase {
    
    /// Assert that an object is properly deallocated after an operation
    /// - Parameters:
    ///   - instance: The object to track
    ///   - file: Source file (auto-filled)
    ///   - line: Source line (auto-filled)
    ///   - operation: The operation to perform
    func assertNoLeak<T: AnyObject>(
        _ instance: T,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> Void
    ) {
        weak var weakInstance = instance
        
        addTeardownBlock { [weak self] in
            XCTAssertNil(
                weakInstance,
                "Memory leak detected: Instance was not deallocated",
                file: file,
                line: line
            )
        }
        
        do {
            try operation()
        } catch {
            XCTFail("Operation threw error: \(error)", file: file, line: line)
        }
    }
    
    /// Assert that an object is properly deallocated after an async operation
    func assertNoLeakAsync<T: AnyObject>(
        _ instance: T,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () async throws -> Void
    ) async {
        weak var weakInstance = instance
        
        addTeardownBlock { [weak self] in
            XCTAssertNil(
                weakInstance,
                "Memory leak detected: Instance was not deallocated",
                file: file,
                line: line
            )
        }
        
        do {
            try await operation()
        } catch {
            XCTFail("Operation threw error: \(error)", file: file, line: line)
        }
    }
    
    /// Track multiple instances for leak detection
    func trackForLeaks<T: AnyObject>(_ instances: [T], file: StaticString = #filePath, line: UInt = #line) {
        let weakReferences = instances.map { WeakBox($0) }
        
        addTeardownBlock {
            for (index, weakBox) in weakReferences.enumerated() {
                XCTAssertNil(
                    weakBox.value,
                    "Memory leak detected at index \(index)",
                    file: file,
                    line: line
                )
            }
        }
    }
}

// MARK: - Actor Isolation Testing

extension XCTestCase {
    
    /// Assert that a closure executes on the main actor
    @MainActor
    func assertMainActor<T>(
        _ closure: @MainActor () throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) rethrows -> T {
        // This function is marked @MainActor, so if we reach here, we're on MainActor
        return try closure()
    }
    
    /// Assert that work completes on main actor after async operation
    func assertCompletesOnMainActor(
        timeout: TimeInterval = 5.0,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: @escaping @MainActor () async -> Void
    ) async {
        let expectation = expectation(description: "Completes on main actor")
        
        Task { @MainActor in
            await operation()
            XCTAssert(Thread.isMainThread, "Not on main thread", file: file, line: line)
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: timeout)
    }
}

// MARK: - Async Testing Helpers

extension XCTestCase {
    
    /// Wait for an async operation with timeout
    func waitAsync(
        timeout: TimeInterval = 5.0,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: @escaping () async throws -> Void
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw TestError.timeout
            }
            
            try await group.next()
            group.cancelAll()
        }
    }
    
    /// Assert that an async operation throws a specific error
    func assertThrowsAsync<T>(
        _ expectedError: Error,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () async throws -> T
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected error but none was thrown", file: file, line: line)
        } catch {
            XCTAssertEqual(
                String(describing: error),
                String(describing: expectedError),
                file: file,
                line: line
            )
        }
    }
    
    /// Assert that an async operation completes without throwing
    func assertNoThrowAsync<T>(
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () async throws -> T
    ) async -> T? {
        do {
            return try await operation()
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
            return nil
        }
    }
}

// MARK: - File System Testing

extension XCTestCase {
    
    /// Create a temporary directory for tests
    func createTemporaryDirectory(file: StaticString = #filePath, line: UInt = #line) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            XCTFail("Failed to create temp directory: \(error)", file: file, line: line)
        }
        
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        return tempDir
    }
    
    /// Assert that temporary files are cleaned up
    func assertTemporaryFilesCleared(
        in directory: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            XCTAssertTrue(
                contents.isEmpty,
                "Directory contains \(contents.count) files: \(contents.map { $0.lastPathComponent })",
                file: file,
                line: line
            )
        } catch {
            XCTFail("Failed to check directory contents: \(error)", file: file, line: line)
        }
    }
    
    /// Create a test audio file
    func createTestAudioFile(
        in directory: URL,
        duration: TimeInterval = 1.0,
        sampleRate: Double = 16000.0
    ) -> URL {
        let fileURL = directory.appendingPathComponent("test_audio_\(UUID().uuidString).wav")
        
        // Create silent audio file
        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        
        do {
            let audioFile = try AVAudioFile(
                forWriting: fileURL,
                settings: format.settings
            )
            try audioFile.write(from: buffer)
        } catch {
            XCTFail("Failed to create test audio file: \(error)")
        }
        
        return fileURL
    }
}

// MARK: - State Machine Testing

extension XCTestCase {
    
    /// Assert that a state transition is valid
    func assertValidTransition<T: Equatable>(
        from oldState: T,
        to newState: T,
        validTransitions: [T: [T]],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let allowedStates = validTransitions[oldState] else {
            XCTFail("No valid transitions defined for state: \(oldState)", file: file, line: line)
            return
        }
        
        XCTAssertTrue(
            allowedStates.contains(newState),
            "Invalid transition from \(oldState) to \(newState). Valid: \(allowedStates)",
            file: file,
            line: line
        )
    }
}

// MARK: - Concurrency Testing

extension XCTestCase {
    
    /// Execute operations concurrently and verify no crashes
    func assertConcurrentExecution(
        iterations: Int = 100,
        timeout: TimeInterval = 30.0,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: @escaping () async -> Void
    ) async {
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<iterations {
                group.addTask {
                    await operation()
                }
            }
            
            await group.waitForAll()
        }
    }
    
    /// Test race condition by executing two operations simultaneously
    func assertNoRaceCondition(
        iterations: Int = 1000,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation1: @escaping () async -> Void,
        operation2: @escaping () async -> Void,
        validation: @escaping () -> Bool
    ) async {
        for iteration in 0..<iterations {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await operation1() }
                group.addTask { await operation2() }
                await group.waitForAll()
            }
            
            XCTAssertTrue(
                validation(),
                "Race condition detected at iteration \(iteration)",
                file: file,
                line: line
            )
        }
    }
}

// MARK: - Helper Types

private class WeakBox<T: AnyObject> {
    weak var value: T?
    
    init(_ value: T) {
        self.value = value
    }
}

enum TestError: Error {
    case timeout
    case invalidState
    case mockError
}

// MARK: - XCTest Additions for macOS 14+

#if compiler(>=5.9)
@available(macOS 14.0, *)
extension XCTestCase {
    /// Modern async fulfillment for expectations
    func fulfillment(
        of expectations: [XCTestExpectation],
        timeout: TimeInterval,
        enforceOrder: Bool = false
    ) async {
        await withCheckedContinuation { continuation in
            wait(for: expectations, timeout: timeout, enforceOrder: enforceOrder)
            continuation.resume()
        }
    }
}
#endif
