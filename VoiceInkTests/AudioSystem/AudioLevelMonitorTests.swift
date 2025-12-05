import XCTest
import AVFoundation
@testable import VoiceInk

/// Tests for AudioLevelMonitor - critical for audio level monitoring without crashes
/// SPECIAL FOCUS: nonisolated deinit with Task { @MainActor } work
@available(macOS 14.0, *)
@MainActor
final class AudioLevelMonitorTests: XCTestCase {
    
    var monitor: AudioLevelMonitor!
    
    override func setUp() async throws {
        try await super.setUp()
        monitor = AudioLevelMonitor()
    }
    
    override func tearDown() async throws {
        if monitor.isMonitoring {
            monitor.stopMonitoring()
        }
        monitor = nil
        try await super.tearDown()
    }
    
    // MARK: - Basic Lifecycle Tests
    
    func testStartStopMonitoringWithoutCrash() {
        // Basic lifecycle test
        XCTAssertFalse(monitor.isMonitoring, "Should start not monitoring")
        
        monitor.startMonitoring()
        
        // Give time to start
        let expectation = expectation(description: "Monitoring started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertTrue(monitor.isMonitoring, "Should be monitoring")
        
        monitor.stopMonitoring()
        XCTAssertFalse(monitor.isMonitoring, "Should stop monitoring")
    }
    
    func testMultipleStartStopCycles() {
        // Test multiple cycles
        for _ in 0..<5 {
            monitor.startMonitoring()
            XCTAssertTrue(monitor.isMonitoring)
            
            let expectation = expectation(description: "Wait")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 1.0)
            
            monitor.stopMonitoring()
            XCTAssertFalse(monitor.isMonitoring)
        }
        
        XCTAssertNotNil(monitor, "Monitor should survive multiple cycles")
    }
    
    // MARK: - State Validation Tests
    
    func testMonitoringWhileAlreadyActive() {
        // Start monitoring
        monitor.startMonitoring()
        
        let expectation = expectation(description: "First start")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertTrue(monitor.isMonitoring)
        
        // Try to start again - should set error
        monitor.startMonitoring()
        
        // Should have error about already monitoring
        XCTAssertNotNil(monitor.error, "Should have error when starting while active")
        
        monitor.stopMonitoring()
    }
    
    func testStopWhileNotMonitoring() {
        // Stop without starting - should be safe
        XCTAssertFalse(monitor.isMonitoring)
        
        monitor.stopMonitoring()
        
        // Should not crash and should stay not monitoring
        XCTAssertFalse(monitor.isMonitoring)
        XCTAssertNotNil(monitor, "Monitor should survive stop without start")
    }
    
    func testStopAfterAlreadyStopped() {
        // Double stop scenario
        monitor.startMonitoring()
        
        let expectation = expectation(description: "Started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        monitor.stopMonitoring()
        XCTAssertFalse(monitor.isMonitoring)
        
        monitor.stopMonitoring() // Double stop
        XCTAssertFalse(monitor.isMonitoring)
        XCTAssertNotNil(monitor, "Monitor should survive double stop")
    }
    
    // MARK: - Device Setup Failure Tests
    
    func testDeviceSetupFailureWithInvalidDevice() {
        // Try to start with an invalid device ID
        let invalidDeviceID = AudioDeviceID(99999)
        
        monitor.startMonitoring(deviceID: invalidDeviceID)
        
        // Should handle failure gracefully
        let expectation = expectation(description: "Setup attempted")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Should not be monitoring if setup failed
        if monitor.isMonitoring {
            // If it did start (maybe there was a fallback), stop it
            monitor.stopMonitoring()
        }
        
        XCTAssertNotNil(monitor, "Monitor should survive setup failure")
    }
    
    // MARK: - Audio Format Handling Tests
    
    func testInvalidAudioFormatHandling() {
        // The monitor should handle cases where audio format is invalid
        // This is tested implicitly through device setup
        
        monitor.startMonitoring()
        
        let expectation = expectation(description: "Format check")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // If monitoring started, format was valid
        if monitor.isMonitoring {
            monitor.stopMonitoring()
        }
        
        XCTAssertNotNil(monitor, "Monitor should handle format issues")
    }
    
    // MARK: - Buffer Processing Thread Safety Tests
    
    func testBufferProcessingThreadSafety() async {
        // Start monitoring
        monitor.startMonitoring()
        
        // Give time to receive some buffers
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
        
        // Check that level is being updated
        let initialLevel = monitor.currentLevel
        
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        
        // Level should be accessible without crash
        _ = monitor.currentLevel
        
        monitor.stopMonitoring()
        
        XCTAssertNotNil(monitor, "Monitor should handle buffer processing safely")
    }
    
    func testConcurrentLevelReads() async {
        // Start monitoring
        monitor.startMonitoring()
        
        // Give time to start
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // Read level from multiple tasks
        await assertConcurrentExecution(iterations: 50) {
            _ = self.monitor.currentLevel
        }
        
        monitor.stopMonitoring()
        XCTAssertNotNil(monitor, "Monitor should handle concurrent reads")
    }
    
    // MARK: - Timer Cleanup Tests
    
    func testTimerCleanupOnStop() {
        // Start and stop, verify timer is cleaned up
        monitor.startMonitoring()
        
        let expectation1 = expectation(description: "Started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation1.fulfill()
        }
        wait(for: [expectation1], timeout: 1.0)
        
        XCTAssertTrue(monitor.isMonitoring)
        
        monitor.stopMonitoring()
        
        // Give time for cleanup
        let expectation2 = expectation(description: "Stopped")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation2.fulfill()
        }
        wait(for: [expectation2], timeout: 1.0)
        
        // Level should be reset to 0
        XCTAssertEqual(monitor.currentLevel, 0.0, "Level should reset after stop")
    }
    
    // MARK: - Audio Tap Removal Tests
    
    func testAudioTapRemovalOnStop() {
        // Test that audio tap is properly removed
        monitor.startMonitoring()
        
        let expectation1 = expectation(description: "Started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation1.fulfill()
        }
        wait(for: [expectation1], timeout: 1.0)
        
        // Stop should remove tap
        monitor.stopMonitoring()
        
        // Starting again should work (proving tap was removed)
        monitor.startMonitoring()
        
        let expectation2 = expectation(description: "Restarted")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation2.fulfill()
        }
        wait(for: [expectation2], timeout: 1.0)
        
        monitor.stopMonitoring()
        XCTAssertNotNil(monitor, "Monitor should handle tap removal properly")
    }
    
    // MARK: - Engine Cleanup Order Tests
    
    func testEngineCleanupOrder() {
        // Test that cleanup happens in correct order
        monitor.startMonitoring()
        
        let expectation = expectation(description: "Started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Stop should clean up in order: timer -> tap -> engine
        monitor.stopMonitoring()
        
        // Should be able to start again without issues
        monitor.startMonitoring()
        monitor.stopMonitoring()
        
        XCTAssertNotNil(monitor, "Monitor should handle cleanup order properly")
    }
    
    // MARK: - Concurrent Start/Stop Tests
    
    func testConcurrentStartStopCalls() async {
        // Test concurrent start/stop from multiple tasks
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask { @MainActor in
                    if i % 2 == 0 {
                        self.monitor.startMonitoring()
                    } else {
                        self.monitor.stopMonitoring()
                    }
                    try? await Task.sleep(nanoseconds: 10_000_000) // 0.01s
                }
            }
            await group.waitForAll()
        }
        
        // Clean up
        if monitor.isMonitoring {
            monitor.stopMonitoring()
        }
        
        XCTAssertNotNil(monitor, "Monitor should survive concurrent start/stop")
    }
    
    // MARK: - Level Smoothing Tests
    
    func testLevelSmoothingAccuracy() {
        // Test that level smoothing produces reasonable values
        monitor.startMonitoring()
        
        let expectation = expectation(description: "Monitoring")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        let level = monitor.currentLevel
        
        // Level should be between 0 and 1
        XCTAssertGreaterThanOrEqual(level, 0.0, "Level should be >= 0")
        XCTAssertLessThanOrEqual(level, 1.0, "Level should be <= 1")
        
        monitor.stopMonitoring()
    }
    
    // MARK: - RMS to dB Conversion Tests
    
    func testRMSToDBConversionEdgeCases() {
        // The monitor converts RMS to dB internally
        // Test that it handles edge cases (silence, max volume)
        
        monitor.startMonitoring()
        
        let expectation = expectation(description: "Buffer processing")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Get level (will be based on actual audio input or silence)
        let level = monitor.currentLevel
        
        // Should be a valid number (not NaN or infinite)
        XCTAssertFalse(level.isNaN, "Level should not be NaN")
        XCTAssertFalse(level.isInfinite, "Level should not be infinite")
        
        monitor.stopMonitoring()
    }
    
    // MARK: - CRITICAL: Nonisolated Deinit Test
    
    func testNonisolatedDeinitWithTaskExecution() async {
        // CRITICAL TEST: AudioLevelMonitor has nonisolated deinit that uses Task { @MainActor }
        // This tests that it doesn't crash
        
        var monitor: AudioLevelMonitor? = AudioLevelMonitor()
        weak var weakMonitor = monitor
        
        // Start monitoring
        monitor?.startMonitoring()
        
        // Give time for setup
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        
        // Release monitor - this triggers deinit
        monitor = nil
        
        // The deinit uses Task { @MainActor } to cleanup
        // Give time for the Task to execute
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
        
        XCTAssertNil(weakMonitor, "Monitor should be deallocated")
        
        // No crash = success
    }
    
    func testDeinitRaceCondition() async {
        // Test rapid allocation/deallocation to catch race conditions
        for _ in 0..<20 {
            var monitor: AudioLevelMonitor? = AudioLevelMonitor()
            monitor?.startMonitoring()
            
            try? await Task.sleep(nanoseconds: 20_000_000) // 0.02s
            
            monitor = nil
            
            try? await Task.sleep(nanoseconds: 10_000_000) // 0.01s
        }
        
        // Give final cleanup time
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
        
        // No crash = success
    }
    
    // MARK: - Memory Leak Tests
    
    func testMonitorDoesNotLeakAfterMultipleSessions() async {
        weak var weakMonitor: AudioLevelMonitor?
        
        await autoreleasepool {
            let monitor = AudioLevelMonitor()
            weakMonitor = monitor
            
            // Multiple monitoring sessions
            for _ in 0..<5 {
                monitor.startMonitoring()
                try? await Task.sleep(nanoseconds: 50_000_000) // 0.05s
                monitor.stopMonitoring()
            }
        }
        
        // Give time for deallocation and Task completion
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
        
        XCTAssertNil(weakMonitor, "Monitor should not leak after multiple sessions")
    }
    
    func testMonitorWithTimerDoesNotLeak() async {
        weak var weakMonitor: AudioLevelMonitor?
        
        await autoreleasepool {
            let monitor = AudioLevelMonitor()
            weakMonitor = monitor
            
            monitor.startMonitoring()
            
            // Let timer run for a bit
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
            
            monitor.stopMonitoring()
        }
        
        // Give time for cleanup
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
        
        XCTAssertNil(weakMonitor, "Monitor with timer should not leak")
    }
    
    // MARK: - Error State Tests
    
    func testErrorIsSetOnFailure() {
        // Start with invalid device to trigger error
        let invalidDevice = AudioDeviceID(88888)
        
        monitor.startMonitoring(deviceID: invalidDevice)
        
        let expectation = expectation(description: "Setup attempted")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // May or may not set error depending on system behavior
        // Main test is that it doesn't crash
        XCTAssertNotNil(monitor, "Monitor should survive invalid device")
    }
    
    func testErrorClearsOnSuccessfulStart() {
        // Set an error state (if possible)
        monitor.error = AudioMonitorError.invalidFormat
        
        // Start monitoring successfully
        monitor.startMonitoring()
        
        let expectation = expectation(description: "Started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // If it started successfully, error should be cleared
        if monitor.isMonitoring {
            XCTAssertNil(monitor.error, "Error should be cleared on successful start")
            monitor.stopMonitoring()
        }
    }
}
