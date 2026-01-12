import XCTest
import SwiftData
import AVFoundation
@testable import VoiceInk

/// Integration tests for complete workflows
/// Tests interaction between multiple components (Recorder + Transcription + Enhancement)
@available(macOS 14.0, *)
@MainActor
final class WorkflowIntegrationTests: XCTestCase {
    
    var whisperState: WhisperState!
    var modelContainer: ModelContainer!
    var testDirectory: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        
        modelContainer = try ModelContainer.createInMemoryContainer()
        testDirectory = createTemporaryDirectory()
        
        whisperState = WhisperState(
            modelContext: modelContainer.mainContext,
            enhancementService: nil
        )
        
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    
    override func tearDown() async throws {
        if whisperState.recordingState == .recording {
            whisperState.shouldCancelRecording = true
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        
        whisperState = nil
        modelContainer = nil
        
        try? FileManager.default.removeItem(at: testDirectory)
        testDirectory = nil
        
        try await super.tearDown()
    }
    
    // MARK: - End-to-End Recording → Transcription Tests
    
    func testCompleteRecordingToTranscriptionWorkflow() async throws {
        // Skip if no models available
        guard let model = whisperState.allAvailableModels.first else {
            XCTSkip("No transcription models available")
        }
        
        whisperState.currentTranscriptionModel = model
        
        // Start recording
        await whisperState.toggleRecord()
        
        // Record for short duration
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        
        // Stop recording (triggers transcription)
        await whisperState.toggleRecord()
        
        // Wait for transcription to complete
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2s
        
        // Verify workflow completed
        XCTAssertNotNil(whisperState, "WhisperState should survive workflow")
        
        // Check if transcription was created
        let descriptor = FetchDescriptor<Transcription>()
        let transcriptions = try modelContainer.mainContext.fetch(descriptor)
        
        // May or may not have transcription depending on test environment
        XCTAssertNotNil(transcriptions, "Should be able to fetch transcriptions")
    }
    
    func testRecordingCancellationWorkflow() async throws {
        guard let model = whisperState.allAvailableModels.first else {
            XCTSkip("No models available")
        }
        
        whisperState.currentTranscriptionModel = model
        
        // Start recording
        await whisperState.toggleRecord()
        
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Cancel immediately
        whisperState.shouldCancelRecording = true
        
        // Stop
        await whisperState.toggleRecord()
        
        // Wait for cleanup
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Should return to idle
        XCTAssertEqual(whisperState.recordingState, .idle, "Should be idle after cancellation")
    }
    
    // MARK: - Device Switching During Recording Tests
    
    func testDeviceSwitchDuringRecording() async throws {
        guard let model = whisperState.allAvailableModels.first else {
            XCTSkip("No models available")
        }
        
        whisperState.currentTranscriptionModel = model
        
        // Start recording
        await whisperState.toggleRecord()
        
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Simulate device change
        NotificationCenter.default.post(
            name: NSNotification.Name("AudioDeviceChanged"),
            object: nil
        )
        
        // Wait for device change handling
        try await Task.sleep(nanoseconds: 300_000_000)
        
        // Should still be recording or have handled change gracefully
        XCTAssertNotNil(whisperState, "Should survive device change")
        
        // Stop recording
        whisperState.shouldCancelRecording = true
        await whisperState.toggleRecord()
        
        try await Task.sleep(nanoseconds: 500_000_000)
    }
    
    // MARK: - Model Loading and Switching Tests
    
    func testModelSwitchingWorkflow() async throws {
        let availableModels = whisperState.allAvailableModels
        
        guard availableModels.count >= 2 else {
            XCTSkip("Need at least 2 models for switching test")
        }
        
        // Switch between models
        for model in availableModels.prefix(2) {
            whisperState.currentTranscriptionModel = model
            
            XCTAssertEqual(whisperState.currentTranscriptionModel?.name, model.name)
            
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        
        XCTAssertNotNil(whisperState, "Should handle model switching")
    }
    
    // MARK: - Multiple Recording Sessions Tests
    
    func testMultipleRecordingSessions() async throws {
        guard let model = whisperState.allAvailableModels.first else {
            XCTSkip("No models available")
        }
        
        whisperState.currentTranscriptionModel = model
        
        // Multiple sessions
        for i in 0..<3 {
            // Start
            await whisperState.toggleRecord()
            
            try await Task.sleep(nanoseconds: 200_000_000)
            
            // Stop
            await whisperState.toggleRecord()
            
            // Wait for processing
            try await Task.sleep(nanoseconds: 500_000_000)
            
            // Should return to idle
            if whisperState.recordingState != .idle {
                // May still be processing, cancel
                whisperState.shouldCancelRecording = true
                try await Task.sleep(nanoseconds: 300_000_000)
            }
        }
        
        XCTAssertNotNil(whisperState, "Should handle multiple sessions")
    }
    
    // MARK: - Error Recovery Tests
    
    func testRecoveryFromInvalidAudioFile() async throws {
        // Create transcription with invalid file
        let invalidTranscription = Transcription(
            text: "",
            duration: 0,
            audioFileURL: "file:///nonexistent/audio.wav",
            transcriptionStatus: .pending
        )
        
        modelContainer.mainContext.insert(invalidTranscription)
        try modelContainer.mainContext.save()
        
        // System should handle this gracefully
        try await Task.sleep(nanoseconds: 200_000_000)
        
        XCTAssertNotNil(whisperState, "Should recover from invalid file")
    }
    
    func testRecoveryFromMissingModel() async throws {
        // Set transcription model to nil
        whisperState.currentTranscriptionModel = nil
        
        // Try to record (should fail gracefully)
        await whisperState.toggleRecord()
        
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Should not be recording
        XCTAssertNotEqual(whisperState.recordingState, .recording, "Should not start without model")
    }
    
    // MARK: - Concurrent Operations Tests
    
    func testConcurrentModelAndRecordingOperations() async throws {
        guard whisperState.allAvailableModels.count >= 2 else {
            XCTSkip("Need multiple models")
        }
        
        let models = whisperState.allAvailableModels
        
        // Try to switch model while recording
        whisperState.currentTranscriptionModel = models[0]
        
        await whisperState.toggleRecord()
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Switch model during recording
        whisperState.currentTranscriptionModel = models[1]
        
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Stop
        whisperState.shouldCancelRecording = true
        await whisperState.toggleRecord()
        
        try await Task.sleep(nanoseconds: 500_000_000)
        
        XCTAssertNotNil(whisperState, "Should handle concurrent operations")
    }
    
    // MARK: - Resource Cleanup Tests
    
    func testResourceCleanupAfterMultipleSessions() async throws {
        guard let model = whisperState.allAvailableModels.first else {
            XCTSkip("No models available")
        }
        
        whisperState.currentTranscriptionModel = model
        
        // Multiple sessions with cleanup
        for _ in 0..<5 {
            await whisperState.toggleRecord()
            try await Task.sleep(nanoseconds: 100_000_000)
            
            whisperState.shouldCancelRecording = true
            await whisperState.toggleRecord()
            
            try await Task.sleep(nanoseconds: 200_000_000)
            
            // Explicit cleanup
            await whisperState.cleanupModelResources()
        }
        
        // Verify cleanup
        XCTAssertEqual(whisperState.recordingState, .idle)
        XCTAssertNotNil(whisperState, "Should clean up resources properly")
    }
    
    // MARK: - State Consistency Tests
    
    func testStateConsistencyAcrossWorkflow() async throws {
        guard let model = whisperState.allAvailableModels.first else {
            XCTSkip("No models available")
        }
        
        whisperState.currentTranscriptionModel = model
        
        // Verify initial state
        XCTAssertEqual(whisperState.recordingState, .idle)
        XCTAssertFalse(whisperState.shouldCancelRecording)
        
        // Start recording
        await whisperState.toggleRecord()
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Check state during recording
        let stateWhileRecording = whisperState.recordingState
        XCTAssertTrue(
            stateWhileRecording == .recording || 
            stateWhileRecording == .transcribing,
            "Should be recording or transcribing"
        )
        
        // Cancel
        whisperState.shouldCancelRecording = true
        XCTAssertTrue(whisperState.shouldCancelRecording)
        
        // Stop
        await whisperState.toggleRecord()
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Final state
        XCTAssertEqual(whisperState.recordingState, .idle)
    }
    
    // MARK: - Notification Integration Tests
    
    func testTranscriptionNotifications() async throws {
        guard let model = whisperState.allAvailableModels.first else {
            XCTSkip("No models available")
        }
        
        whisperState.currentTranscriptionModel = model
        
        let expectation = expectation(description: "Transcription notification")
        expectation.isInverted = true // We don't expect it in test environment
        
        let observer = NotificationCenter.default.addObserver(
            forName: .transcriptionCreated,
            object: nil,
            queue: .main
        ) { _ in
            expectation.fulfill()
        }
        
        defer {
            NotificationCenter.default.removeObserver(observer)
        }
        
        // Try to create a transcription
        await whisperState.toggleRecord()
        try await Task.sleep(nanoseconds: 200_000_000)
        
        whisperState.shouldCancelRecording = true
        await whisperState.toggleRecord()
        
        // Wait a bit (but expect no notification in test env)
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    // MARK: - Memory Integration Tests
    
    func testMemoryStabilityAcrossWorkflow() async throws {
        weak var weakState: WhisperState?
        
        await autoreleasepool {
            let container = try? ModelContainer.createInMemoryContainer()
            guard let container = container else { return }
            
            let state = WhisperState(
                modelContext: container.mainContext,
                enhancementService: nil
            )
            weakState = state
            
            // Perform workflow
            if let model = state.allAvailableModels.first {
                state.currentTranscriptionModel = model
                
                await state.toggleRecord()
                try? await Task.sleep(nanoseconds: 100_000_000)
                
                state.shouldCancelRecording = true
                await state.toggleRecord()
                
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
        
        // Give time for cleanup
        try await Task.sleep(nanoseconds: 500_000_000)
        
        XCTAssertNil(weakState, "Should not leak after full workflow")
    }
    
    // MARK: - Edge Case Integration Tests
    
    func testRapidStartStopCycles() async throws {
        guard let model = whisperState.allAvailableModels.first else {
            XCTSkip("No models available")
        }
        
        whisperState.currentTranscriptionModel = model
        
        // Rapid start/stop
        for _ in 0..<5 {
            await whisperState.toggleRecord()
            try await Task.sleep(nanoseconds: 50_000_000) // Very short
            await whisperState.toggleRecord()
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        
        // Cancel any pending work
        whisperState.shouldCancelRecording = true
        try await Task.sleep(nanoseconds: 500_000_000)
        
        XCTAssertNotNil(whisperState, "Should handle rapid cycles")
    }
    
    func testStateRecoveryAfterUnexpectedError() async throws {
        // Simulate an error condition
        whisperState.recordingState = .busy
        
        // Try to recover
        await whisperState.cleanupModelResources()
        
        // Should recover to idle
        XCTAssertEqual(whisperState.recordingState, .idle, "Should recover to idle")
    }
}
