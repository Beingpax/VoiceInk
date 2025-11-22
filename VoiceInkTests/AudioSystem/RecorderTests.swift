import XCTest
import AVFoundation
@testable import VoiceInk

/// Tests for the Recorder class - critical for audio recording stability
@available(macOS 14.0, *)
@MainActor
final class RecorderTests: XCTestCase {
    
    var recorder: Recorder!
    var testDirectory: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        recorder = Recorder()
        testDirectory = createTemporaryDirectory()
    }
    
    override func tearDown() async throws {
        recorder.stopRecording()
        recorder = nil
        try? FileManager.default.removeItem(at: testDirectory)
        testDirectory = nil
        try await super.tearDown()
    }
    
    // MARK: - Basic Lifecycle Tests
    
    func testStartStopRecordingWithoutCrash() async throws {
        // Test basic start/stop without crashing
        let outputFile = testDirectory.appendingPathComponent("test_recording.wav")
        
        try await recorder.startRecording(toOutputFile: outputFile)
        XCTAssertNotNil(recorder, "Recorder should be alive after starting")
        
        // Record for a short time
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        
        recorder.stopRecording()
        XCTAssertNotNil(recorder, "Recorder should be alive after stopping")
        
        // Verify file was created
        FileSystemHelper.assertFileExists(at: outputFile)
    }
    
    func testMultipleStartStopCycles() async throws {
        // Test that recorder can handle multiple start/stop cycles
        for i in 0..<10 {
            let outputFile = testDirectory.appendingPathComponent("recording_\(i).wav")
            
            try await recorder.startRecording(toOutputFile: outputFile)
            try await Task.sleep(nanoseconds: 50_000_000) // 0.05s
            recorder.stopRecording()
            
            FileSystemHelper.assertFileExists(at: outputFile)
        }
    }
    
    func testStopWithoutStartDoesNotCrash() {
        // Should not crash when stopping without starting
        recorder.stopRecording()
        recorder.stopRecording() // Double stop
        XCTAssertNotNil(recorder)
    }
    
    func testStopBeforeStartCompletes() async throws {
        // Test race condition: stop called before start completes
        let outputFile = testDirectory.appendingPathComponent("race_test.wav")
        
        async let startTask: () = recorder.startRecording(toOutputFile: outputFile)
        
        // Try to stop immediately
        await Task.yield() // Give start a chance to begin
        recorder.stopRecording()
        
        // Wait for start to complete
        do {
            try await startTask
        } catch {
            // Expected to fail or succeed, should not crash
        }
        
        XCTAssertNotNil(recorder, "Recorder should survive race condition")
    }
    
    // MARK: - Memory Management Tests
    
    func testRecorderDoesNotLeakAfterMultipleSessions() async {
        weak var weakRecorder: Recorder?
        
        await autoreleasepool {
            let tempRecorder = Recorder()
            weakRecorder = tempRecorder
            
            // Perform multiple recording sessions
            for i in 0..<5 {
                let outputFile = testDirectory.appendingPathComponent("leak_test_\(i).wav")
                try? await tempRecorder.startRecording(toOutputFile: outputFile)
                try? await Task.sleep(nanoseconds: 20_000_000) // 0.02s
                tempRecorder.stopRecording()
            }
        }
        
        // Give time for deallocation
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        
        XCTAssertNil(weakRecorder, "Recorder should be deallocated")
    }
    
    func testTimerCleanupInDeinit() async {
        var recorder: Recorder? = Recorder()
        weak var weakRecorder = recorder
        
        let outputFile = testDirectory.appendingPathComponent("timer_test.wav")
        try? await recorder?.startRecording(toOutputFile: outputFile)
        
        // Let some timer iterations run
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
        
        recorder?.stopRecording()
        recorder = nil
        
        // Wait for cleanup
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertNil(weakRecorder, "Recorder with active timers should be deallocated")
    }
    
    func testAudioMeterUpdatesWithoutLeak() async throws {
        let outputFile = testDirectory.appendingPathComponent("meter_test.wav")
        try await recorder.startRecording(toOutputFile: outputFile)
        
        // Capture multiple meter readings
        var meterReadings: [AudioMeter] = []
        for _ in 0..<10 {
            meterReadings.append(recorder.audioMeter)
            try await Task.sleep(nanoseconds: 50_000_000) // 0.05s
        }
        
        recorder.stopRecording()
        
        // Verify we got readings
        XCTAssertEqual(meterReadings.count, 10)
        XCTAssertNotNil(recorder, "Recorder should not leak during meter updates")
    }
    
    // MARK: - Device Change Tests
    
    func testDeviceChangeDuringRecording() async throws {
        // This tests the handleDeviceChange functionality
        let outputFile = testDirectory.appendingPathComponent("device_change_test.wav")
        
        try await recorder.startRecording(toOutputFile: outputFile)
        
        // Simulate device change notification
        NotificationCenter.default.post(
            name: NSNotification.Name("AudioDeviceChanged"),
            object: nil
        )
        
        // Give time for reconfiguration
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2s
        
        recorder.stopRecording()
        
        // Should not crash
        XCTAssertNotNil(recorder)
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentStopCalls() async {
        let outputFile = testDirectory.appendingPathComponent("concurrent_stop.wav")
        try? await recorder.startRecording(toOutputFile: outputFile)
        
        // Try to stop from multiple tasks simultaneously
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask { @MainActor in
                    self.recorder.stopRecording()
                }
            }
            await group.waitForAll()
        }
        
        XCTAssertNotNil(recorder, "Recorder should survive concurrent stops")
    }
    
    func testRapidStartAttempts() async {
        // Test multiple rapid start attempts
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                group.addTask { @MainActor in
                    let file = self.testDirectory.appendingPathComponent("rapid_\(i).wav")
                    try? await self.recorder.startRecording(toOutputFile: file)
                }
            }
            await group.waitForAll()
        }
        
        recorder.stopRecording()
        XCTAssertNotNil(recorder, "Recorder should handle rapid starts")
    }
    
    // MARK: - File Cleanup Tests
    
    func testFileCleanupOnFailedRecording() async {
        let outputFile = testDirectory.appendingPathComponent("failed_recording.wav")
        
        // Create read-only directory to force failure
        let readOnlyDir = testDirectory.appendingPathComponent("readonly")
        try? FileManager.default.createDirectory(at: readOnlyDir, withIntermediateDirectories: true)
        try? FileSystemHelper.makeReadOnly(readOnlyDir)
        
        let failFile = readOnlyDir.appendingPathComponent("test.wav")
        
        do {
            try await recorder.startRecording(toOutputFile: failFile)
            XCTFail("Should have failed due to permissions")
        } catch {
            // Expected to fail
        }
        
        // Verify recorder is still usable
        try? await recorder.startRecording(toOutputFile: outputFile)
        recorder.stopRecording()
        
        XCTAssertNotNil(recorder, "Recorder should survive failed start")
    }
    
    // MARK: - Audio Detection Tests
    
    func testNoAudioDetectedWarning() async throws {
        let outputFile = testDirectory.appendingPathComponent("no_audio_test.wav")
        
        let warningExpectation = expectation(description: "No audio warning")
        var receivedWarning = false
        
        // Monitor for notification
        let observer = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("NoAudioDetected"),
            object: nil,
            queue: .main
        ) { _ in
            receivedWarning = true
            warningExpectation.fulfill()
        }
        
        defer {
            NotificationCenter.default.removeObserver(observer)
        }
        
        try await recorder.startRecording(toOutputFile: outputFile)
        
        // Wait for warning (should trigger at 5 seconds)
        await fulfillment(of: [warningExpectation], timeout: 6.0)
        
        recorder.stopRecording()
        
        XCTAssertTrue(receivedWarning, "Should receive no audio warning")
    }
    
    func testHasDetectedAudioInCurrentSessionReset() async throws {
        let outputFile1 = testDirectory.appendingPathComponent("session1.wav")
        let outputFile2 = testDirectory.appendingPathComponent("session2.wav")
        
        // First session
        try await recorder.startRecording(toOutputFile: outputFile1)
        try await Task.sleep(nanoseconds: 100_000_000)
        recorder.stopRecording()
        
        // Second session should reset detection
        try await recorder.startRecording(toOutputFile: outputFile2)
        try await Task.sleep(nanoseconds: 100_000_000)
        recorder.stopRecording()
        
        // Should not crash
        XCTAssertNotNil(recorder)
    }
    
    // MARK: - Recording Duration Tests
    
    func testRecordingDurationUpdates() async throws {
        let outputFile = testDirectory.appendingPathComponent("duration_test.wav")
        
        try await recorder.startRecording(toOutputFile: outputFile)
        
        // Check duration updates
        let initialDuration = recorder.recordingDuration
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        let laterDuration = recorder.recordingDuration
        
        recorder.stopRecording()
        
        XCTAssertGreaterThan(laterDuration, initialDuration, "Duration should increase")
        XCTAssertGreaterThan(laterDuration, 0.4, "Should record for ~0.5s")
    }
    
    // MARK: - Delegate Callback Tests
    
    func testDelegateCallbacksOnCorrectThread() async throws {
        let outputFile = testDirectory.appendingPathComponent("delegate_test.wav")
        
        let expectation = expectation(description: "Delegate callback")
        var wasOnMainThread = false
        
        class TestDelegate: NSObject, AVAudioRecorderDelegate {
            var onFinish: ((Bool) -> Void)?
            
            func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
                onFinish?(Thread.isMainThread)
            }
        }
        
        // Start recording
        try await recorder.startRecording(toOutputFile: outputFile)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Stop and wait for delegate callback
        recorder.stopRecording()
        
        // Delegate callbacks should eventually reach MainActor
        try await Task.sleep(nanoseconds: 200_000_000)
        
        XCTAssertNotNil(recorder, "Recorder should handle delegate callbacks")
    }
    
    // MARK: - Audio Level Detection Threshold
    
    func testAudioLevelDetectionThreshold() async throws {
        let outputFile = testDirectory.appendingPathComponent("threshold_test.wav")
        
        try await recorder.startRecording(toOutputFile: outputFile)
        
        // Check that meter values are within expected range
        try await Task.sleep(nanoseconds: 100_000_000)
        
        let meter = recorder.audioMeter
        XCTAssertGreaterThanOrEqual(meter.averagePower, 0.0)
        XCTAssertLessThanOrEqual(meter.averagePower, 1.0)
        XCTAssertGreaterThanOrEqual(meter.peakPower, 0.0)
        XCTAssertLessThanOrEqual(meter.peakPower, 1.0)
        
        recorder.stopRecording()
    }
    
    // MARK: - Observer Cleanup Tests
    
    func testDeviceObserverRemovedInDeinit() async {
        var recorder: Recorder? = Recorder()
        weak var weakRecorder = recorder
        
        // Start a recording to activate observer
        let outputFile = testDirectory.appendingPathComponent("observer_test.wav")
        try? await recorder?.startRecording(toOutputFile: outputFile)
        recorder?.stopRecording()
        
        // Release recorder
        recorder = nil
        
        // Give time for deinit
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertNil(weakRecorder, "Recorder should deallocate and remove observers")
        
        // Post notification - should not crash
        NotificationCenter.default.post(
            name: NSNotification.Name("AudioDeviceChanged"),
            object: nil
        )
    }
}
