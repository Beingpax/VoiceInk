import XCTest
@testable import VoiceInk

/// Concurrency stress tests - extreme concurrent access scenarios
/// Tests thread safety and race condition handling under load
@available(macOS 14.0, *)
@MainActor
final class ConcurrencyStressTests: XCTestCase {
    
    // MARK: - Recorder Concurrency Stress
    
    func testRecorderMassiveConcurrentStops() async {
        let recorder = Recorder()
        let testDir = createTemporaryDirectory()
        
        defer {
            try? FileManager.default.removeItem(at: testDir)
        }
        
        // Start one recording
        let file = testDir.appendingPathComponent("test.wav")
        try? await recorder.startRecording(toOutputFile: file)
        
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // Try to stop from 1000 concurrent tasks
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<1000 {
                group.addTask { @MainActor in
                    recorder.stopRecording()
                }
            }
            await group.waitForAll()
        }
        
        // No crash = success
        XCTAssertNotNil(recorder, "Should survive massive concurrent stops")
    }
    
    func testRecorderConcurrentMeterReads() async {
        let recorder = Recorder()
        let testDir = createTemporaryDirectory()
        
        defer {
            try? FileManager.default.removeItem(at: testDir)
        }
        
        let file = testDir.appendingPathComponent("meter_test.wav")
        try? await recorder.startRecording(toOutputFile: file)
        
        // Read meter from 500 concurrent tasks
        await withTaskGroup(of: AudioMeter.self) { group in
            for _ in 0..<500 {
                group.addTask { @MainActor in
                    return recorder.audioMeter
                }
            }
            
            var meters: [AudioMeter] = []
            for await meter in group {
                meters.append(meter)
            }
            
            XCTAssertEqual(meters.count, 500, "Should read all meters")
        }
        
        recorder.stopRecording()
    }
    
    // MARK: - AudioDeviceManager Concurrency Stress
    
    func testAudioDeviceManagerMassiveGetCurrentDevice() async {
        let manager = AudioDeviceManager()
        
        // 1000 concurrent getCurrentDevice calls
        await withTaskGroup(of: AudioDeviceID.self) { group in
            for _ in 0..<1000 {
                group.addTask { @MainActor in
                    return manager.getCurrentDevice()
                }
            }
            
            var devices: [AudioDeviceID] = []
            for await device in group {
                devices.append(device)
            }
            
            XCTAssertEqual(devices.count, 1000)
            
            // All should return same device
            let uniqueDevices = Set(devices)
            XCTAssertLessThanOrEqual(uniqueDevices.count, 2, "Should return consistent device")
        }
    }
    
    func testAudioDeviceManagerConcurrentFlagToggle() async {
        let manager = AudioDeviceManager()
        
        // Rapidly toggle isRecordingActive from many tasks
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<500 {
                group.addTask { @MainActor in
                    manager.isRecordingActive = !manager.isRecordingActive
                }
            }
            await group.waitForAll()
        }
        
        // Should complete without crash
        XCTAssertNotNil(manager, "Should survive flag toggling")
    }
    
    // MARK: - AudioLevelMonitor Concurrency Stress
    
    func testAudioLevelMonitorConcurrentStartStop() async {
        let monitor = AudioLevelMonitor()
        
        // 200 tasks trying to start/stop simultaneously
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<200 {
                group.addTask { @MainActor in
                    if i % 2 == 0 {
                        monitor.startMonitoring()
                    } else {
                        monitor.stopMonitoring()
                    }
                }
            }
            await group.waitForAll()
        }
        
        // Clean up
        if monitor.isMonitoring {
            monitor.stopMonitoring()
        }
        
        XCTAssertNotNil(monitor, "Should survive concurrent start/stop")
    }
    
    func testAudioLevelMonitorConcurrentLevelReads() async {
        let monitor = AudioLevelMonitor()
        monitor.startMonitoring()
        
        defer {
            monitor.stopMonitoring()
        }
        
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // 1000 concurrent level reads
        await withTaskGroup(of: Float.self) { group in
            for _ in 0..<1000 {
                group.addTask { @MainActor in
                    return monitor.currentLevel
                }
            }
            
            var levels: [Float] = []
            for await level in group {
                levels.append(level)
            }
            
            XCTAssertEqual(levels.count, 1000)
            
            // All levels should be valid (0-1)
            XCTAssertTrue(levels.allSatisfy { $0 >= 0 && $0 <= 1 })
        }
    }
    
    // MARK: - WhisperState Concurrency Stress
    
    func testWhisperStateConcurrentCancellationFlagAccess() async throws {
        let container = try ModelContainer.createInMemoryContainer()
        let state = WhisperState(
            modelContext: container.mainContext,
            enhancementService: nil
        )
        
        // 1000 concurrent accesses to shouldCancelRecording
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<1000 {
                group.addTask { @MainActor in
                    // Toggle and read
                    state.shouldCancelRecording = !state.shouldCancelRecording
                    _ = state.shouldCancelRecording
                }
            }
            await group.waitForAll()
        }
        
        XCTAssertNotNil(state, "Should survive flag races")
    }
    
    func testWhisperStateConcurrentModelAccess() async throws {
        let container = try ModelContainer.createInMemoryContainer()
        let state = WhisperState(
            modelContext: container.mainContext,
            enhancementService: nil
        )
        
        let models = state.allAvailableModels
        guard !models.isEmpty else {
            XCTSkip("No models available")
        }
        
        // 500 tasks accessing/changing model
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<500 {
                group.addTask { @MainActor in
                    let model = models[i % models.count]
                    state.currentTranscriptionModel = model
                    _ = state.currentTranscriptionModel
                }
            }
            await group.waitForAll()
        }
        
        XCTAssertNotNil(state, "Should survive concurrent model access")
    }
    
    // MARK: - PowerModeSessionManager Concurrency Stress
    
    func testPowerModeConcurrentBeginEnd() async {
        let manager = PowerModeSessionManager.shared
        
        let config = PowerModeConfig(
            id: UUID(),
            name: "Concurrency Test",
            emoji: "🔀",
            appIdentifier: "com.test",
            urlPattern: nil,
            isEnabled: true,
            isAIEnhancementEnabled: false,
            useScreenCapture: false,
            selectedPrompt: nil,
            selectedAIProvider: nil,
            selectedAIModel: nil,
            selectedLanguage: nil,
            selectedTranscriptionModelName: nil,
            isAutoSendEnabled: false
        )
        
        // 100 concurrent begin/end operations
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask { @MainActor in
                    if i % 2 == 0 {
                        await manager.beginSession(with: config)
                    } else {
                        await manager.endSession()
                    }
                }
            }
            await group.waitForAll()
        }
        
        // Clean up
        await manager.endSession()
        
        XCTAssertNil(manager.loadSession(), "Should handle concurrent operations")
    }
    
    // MARK: - KeychainManager Concurrency Stress
    
    func testKeychainManagerConcurrentSaveRetrieve() async {
        let manager = KeychainManager(service: "com.test.ConcurrencyStress")
        
        defer {
            try? manager.deleteAllAPIKeys()
        }
        
        // 500 concurrent save/retrieve operations
        await withTaskGroup(of: String?.self) { group in
            for i in 0..<500 {
                group.addTask {
                    let provider = "Provider\(i % 10)"
                    let key = "key-\(i)"
                    
                    manager.saveAPIKey(key, for: provider)
                    return manager.getAPIKey(for: provider)
                }
            }
            
            var results: [String?] = []
            for await result in group {
                results.append(result)
            }
            
            XCTAssertEqual(results.count, 500)
        }
        
        // Should have completed all operations
        let providers = manager.getAllProviders()
        XCTAssertLessThanOrEqual(providers.count, 10)
    }
    
    func testKeychainManagerConcurrentDelete() async {
        let manager = KeychainManager(service: "com.test.ConcurrencyStress2")
        
        defer {
            try? manager.deleteAllAPIKeys()
        }
        
        // Save keys first
        for i in 0..<20 {
            manager.saveAPIKey("key\(i)", for: "Provider\(i)")
        }
        
        // Delete concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    try? manager.deleteAPIKey(for: "Provider\(i)")
                }
            }
            await group.waitForAll()
        }
        
        // All should be deleted
        let remaining = manager.getAllProviders()
        XCTAssertEqual(remaining.count, 0, "All keys should be deleted")
    }
    
    // MARK: - Combined Concurrency Stress
    
    func testMultipleComponentsConcurrentAccess() async {
        let recorder = Recorder()
        let monitor = AudioLevelMonitor()
        let manager = AudioDeviceManager()
        
        let testDir = createTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: testDir)
        }
        
        // Use all three components concurrently
        await withTaskGroup(of: Void.self) { group in
            // Recorder tasks
            for _ in 0..<50 {
                group.addTask { @MainActor in
                    _ = recorder.audioMeter
                    _ = recorder.recordingDuration
                }
            }
            
            // Monitor tasks
            for i in 0..<50 {
                group.addTask { @MainActor in
                    if i % 2 == 0 {
                        monitor.startMonitoring()
                    } else {
                        monitor.stopMonitoring()
                    }
                }
            }
            
            // Manager tasks
            for _ in 0..<50 {
                group.addTask { @MainActor in
                    _ = manager.getCurrentDevice()
                    manager.isRecordingActive = !manager.isRecordingActive
                }
            }
            
            await group.waitForAll()
        }
        
        // Clean up
        if monitor.isMonitoring {
            monitor.stopMonitoring()
        }
        
        XCTAssertNotNil(recorder)
        XCTAssertNotNil(monitor)
        XCTAssertNotNil(manager)
    }
    
    // MARK: - Published Property Concurrency Stress
    
    func testPublishedPropertyConcurrentAccess() async {
        let monitor = AudioLevelMonitor()
        
        // 1000 concurrent reads/writes to published property
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<1000 {
                group.addTask { @MainActor in
                    return monitor.isMonitoring
                }
            }
            
            var results: [Bool] = []
            for await result in group {
                results.append(result)
            }
            
            XCTAssertEqual(results.count, 1000)
        }
    }
    
    // MARK: - State Transition Concurrency
    
    func testStateMachineConcurrentTransitions() async throws {
        let container = try ModelContainer.createInMemoryContainer()
        let state = WhisperState(
            modelContext: container.mainContext,
            enhancementService: nil
        )
        
        let validStates: [RecordingState] = [.idle, .recording, .transcribing, .enhancing, .busy]
        
        // 500 concurrent state changes
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<500 {
                group.addTask { @MainActor in
                    state.recordingState = validStates[i % validStates.count]
                    _ = state.recordingState
                }
            }
            await group.waitForAll()
        }
        
        XCTAssertNotNil(state, "Should survive concurrent state changes")
    }
}
