import XCTest
import SwiftData
@testable import VoiceInk

/// Stress tests for memory leak detection
/// Runs components through extreme usage scenarios to detect leaks
@available(macOS 14.0, *)
@MainActor
final class MemoryStressTests: XCTestCase {
    
    // MARK: - Recorder Memory Stress
    
    func testRecorderHundredSessions() async {
        weak var weakRecorder: Recorder?
        let testDir = createTemporaryDirectory()
        
        defer {
            try? FileManager.default.removeItem(at: testDir)
        }
        
        await autoreleasepool {
            let recorder = Recorder()
            weakRecorder = recorder
            
            for i in 0..<100 {
                let file = testDir.appendingPathComponent("rec_\(i).wav")
                try? await recorder.startRecording(toOutputFile: file)
                try? await Task.sleep(nanoseconds: 20_000_000) // 0.02s
                recorder.stopRecording()
            }
        }
        
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        XCTAssertNil(weakRecorder, "Recorder should not leak after 100 sessions")
    }
    
    func testRecorderRapidAllocDealloc() async {
        for _ in 0..<50 {
            await autoreleasepool {
                let recorder = Recorder()
                _ = recorder.audioMeter
                _ = recorder.recordingDuration
            }
            
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        
        // No crash = success, all properly deallocated
    }
    
    // MARK: - AudioDeviceManager Memory Stress
    
    func testAudioDeviceManagerMultipleInstances() async {
        var weakManagers: [AudioDeviceManager?] = []
        
        await autoreleasepool {
            for _ in 0..<20 {
                let manager = AudioDeviceManager()
                weakManagers.append(manager)
                
                // Use manager
                _ = manager.getCurrentDevice()
                manager.loadAvailableDevices { }
                
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        // All should be nil
        let leakedCount = weakManagers.compactMap { $0 }.count
        XCTAssertEqual(leakedCount, 0, "No managers should leak")
    }
    
    // MARK: - AudioLevelMonitor Memory Stress
    
    func testAudioLevelMonitorExtremeCycles() async {
        weak var weakMonitor: AudioLevelMonitor?
        
        await autoreleasepool {
            let monitor = AudioLevelMonitor()
            weakMonitor = monitor
            
            for _ in 0..<100 {
                monitor.startMonitoring()
                try? await Task.sleep(nanoseconds: 50_000_000)
                monitor.stopMonitoring()
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }
        
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        XCTAssertNil(weakMonitor, "Monitor should not leak after 100 cycles")
    }
    
    func testAudioLevelMonitorRapidCreation() async {
        // Test the critical deinit race under stress
        for _ in 0..<100 {
            await autoreleasepool {
                let monitor = AudioLevelMonitor()
                monitor.startMonitoring()
                try? await Task.sleep(nanoseconds: 20_000_000)
                // Deinit triggers while monitoring
            }
            
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        
        // No crash = deinit race condition handled properly
    }
    
    // MARK: - WhisperState Memory Stress
    
    func testWhisperStateMultipleInstances() async {
        var weakStates: [WhisperState?] = []
        
        await autoreleasepool {
            for _ in 0..<10 {
                let container = try? ModelContainer.createInMemoryContainer()
                guard let container = container else { continue }
                
                let state = WhisperState(
                    modelContext: container.mainContext,
                    enhancementService: nil
                )
                weakStates.append(state)
                
                _ = state.recordingState
                _ = state.allAvailableModels
                
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s
        
        let leakedCount = weakStates.compactMap { $0 }.count
        XCTAssertEqual(leakedCount, 0, "WhisperStates should not leak")
    }
    
    // MARK: - TTSViewModel Memory Stress
    
    func testTTSViewModelHundredInstances() async {
        for _ in 0..<100 {
            await autoreleasepool {
                let vm = TTSViewModel()
                vm.inputText = "Test text for memory stress"
                _ = vm.availableVoices
                _ = vm.currentCharacterLimit
            }
            
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        
        // All instances should be deallocated
        // No crash = success
    }
    
    func testTTSViewModelWithActivePublishers() async {
        weak var weakVM: TTSViewModel?
        
        await autoreleasepool {
            let vm = TTSViewModel()
            weakVM = vm
            
            var cancellables = Set<AnyCancellable>()
            
            // Subscribe to many publishers
            vm.$isGenerating.sink { _ in }.store(in: &cancellables)
            vm.$isPlaying.sink { _ in }.store(in: &cancellables)
            vm.$currentTime.sink { _ in }.store(in: &cancellables)
            vm.$inputText.sink { _ in }.store(in: &cancellables)
            
            // Trigger updates
            for i in 0..<50 {
                vm.inputText = "Text \(i)"
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            
            cancellables.removeAll()
        }
        
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        XCTAssertNil(weakVM, "ViewModel should not leak with publishers")
    }
    
    // MARK: - PowerModeSessionManager Memory Stress
    
    func testPowerModeMultipleSessions() async {
        let manager = PowerModeSessionManager.shared
        
        let config = PowerModeConfig(
            id: UUID(),
            name: "Stress Test",
            emoji: "⚡",
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
        
        for _ in 0..<50 {
            await manager.beginSession(with: config)
            try? await Task.sleep(nanoseconds: 50_000_000)
            await manager.endSession()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        
        // Should complete without leaking
        XCTAssertNil(manager.loadSession(), "Should have no active session")
    }
    
    // MARK: - KeychainManager Memory Stress
    
    func testKeychainManagerMassiveOperations() {
        let manager = KeychainManager(service: "com.test.MemoryStress")
        
        defer {
            try? manager.deleteAllAPIKeys()
        }
        
        // Massive save/retrieve/delete cycles
        for i in 0..<1000 {
            let provider = "Provider\(i % 10)" // 10 different providers
            let key = "key-\(i)"
            
            manager.saveAPIKey(key, for: provider)
            _ = manager.getAPIKey(for: provider)
            
            if i % 100 == 0 {
                try? manager.deleteAPIKey(for: provider)
            }
        }
        
        // Should complete without issues
        let providers = manager.getAllProviders()
        XCTAssertLessThanOrEqual(providers.count, 10, "Should have max 10 providers")
    }
    
    // MARK: - Combined Component Memory Stress
    
    func testCombinedComponentsMemoryStability() async {
        weak var weakRecorder: Recorder?
        weak var weakMonitor: AudioLevelMonitor?
        weak var weakManager: AudioDeviceManager?
        
        await autoreleasepool {
            let recorder = Recorder()
            let monitor = AudioLevelMonitor()
            let manager = AudioDeviceManager()
            
            weakRecorder = recorder
            weakMonitor = monitor
            weakManager = manager
            
            // Use all components together
            for _ in 0..<20 {
                monitor.startMonitoring()
                _ = manager.getCurrentDevice()
                _ = recorder.audioMeter
                
                try? await Task.sleep(nanoseconds: 50_000_000)
                
                monitor.stopMonitoring()
            }
        }
        
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        XCTAssertNil(weakRecorder, "Recorder should not leak")
        XCTAssertNil(weakMonitor, "Monitor should not leak")
        XCTAssertNil(weakManager, "Manager should not leak")
    }
    
    // MARK: - Timer Cleanup Stress
    
    func testTimerCleanupUnderStress() async {
        // Create many components with timers
        for _ in 0..<50 {
            await autoreleasepool {
                let recorder = Recorder()
                let monitor = AudioLevelMonitor()
                let testDir = createTemporaryDirectory()
                
                // Start timers
                let file = testDir.appendingPathComponent("test.wav")
                try? await recorder.startRecording(toOutputFile: file)
                monitor.startMonitoring()
                
                try? await Task.sleep(nanoseconds: 100_000_000)
                
                // Stop (cleanup timers)
                recorder.stopRecording()
                monitor.stopMonitoring()
                
                try? FileManager.default.removeItem(at: testDir)
            }
            
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        
        // All timers should be cleaned up
        // No crash or hanging = success
    }
    
    // MARK: - NotificationCenter Observer Stress
    
    func testNotificationObserverCleanupStress() async {
        // Create many components that use NotificationCenter
        for _ in 0..<100 {
            await autoreleasepool {
                let manager = AudioDeviceManager()
                _ = manager.getCurrentDevice()
                
                // Manager registers observers in init
                // Should cleanup in deinit
            }
            
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        
        // Post notification - should not crash
        NotificationCenter.default.post(
            name: NSNotification.Name("AudioDeviceChanged"),
            object: nil
        )
        
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // No crash = observers properly cleaned up
    }
    
    // MARK: - File Handle Stress
    
    func testFileHandleStress() async {
        let testDir = createTemporaryDirectory()
        
        defer {
            try? FileManager.default.removeItem(at: testDir)
        }
        
        // Create many audio files rapidly
        for i in 0..<100 {
            await autoreleasepool {
                let recorder = Recorder()
                let file = testDir.appendingPathComponent("stress_\(i).wav")
                
                try? await recorder.startRecording(toOutputFile: file)
                try? await Task.sleep(nanoseconds: 50_000_000)
                recorder.stopRecording()
            }
        }
        
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        // Should not exhaust file handles
        // Can still create files
        let testFile = testDir.appendingPathComponent("final_test.txt")
        let data = "test".data(using: .utf8)!
        
        XCTAssertNoThrow(try data.write(to: testFile), "Should still be able to write files")
    }
    
    // MARK: - SwiftData Context Stress
    
    func testSwiftDataContextStress() async throws {
        let container = try ModelContainer.createInMemoryContainer()
        
        // Create many transcriptions rapidly
        for i in 0..<1000 {
            await autoreleasepool {
                let transcription = Transcription(
                    text: "Stress test \(i)",
                    duration: 1.0,
                    audioFileURL: "file:///test_\(i).wav",
                    transcriptionStatus: .completed
                )
                
                container.mainContext.insert(transcription)
                
                if i % 100 == 0 {
                    try? container.mainContext.save()
                }
            }
        }
        
        try container.mainContext.save()
        
        // Fetch all
        let descriptor = FetchDescriptor<Transcription>()
        let all = try container.mainContext.fetch(descriptor)
        
        XCTAssertEqual(all.count, 1000, "Should have all transcriptions")
    }
}
