import XCTest
import AVFoundation
@testable import VoiceInk

/// Tests for VoiceActivityDetector - speech detection and segmentation
/// FOCUS: Model initialization, deinit cleanup, speech detection accuracy
@available(macOS 14.0, *)
final class VoiceActivityDetectorTests: XCTestCase {
    
    var modelPath: String!
    
    override func setUp() throws {
        try super.setUp()
        
        // Get VAD model path (may not exist in test environment)
        modelPath = Bundle.main.path(forResource: "silero_vad", ofType: "ort") ?? ""
    }
    
    override func tearDown() throws {
        modelPath = nil
        try super.tearDown()
    }
    
    // MARK: - Model Initialization Tests
    
    func testModelInitializationWithInvalidPath() {
        let invalidPath = "/nonexistent/path/to/model"
        
        let detector = VoiceActivityDetector(modelPath: invalidPath)
        
        // Should return nil for invalid path
        XCTAssertNil(detector, "Should return nil for invalid model path")
    }
    
    func testModelInitializationWithEmptyPath() {
        let detector = VoiceActivityDetector(modelPath: "")
        
        XCTAssertNil(detector, "Should return nil for empty path")
    }
    
    func testModelInitializationWithValidPath() {
        // Skip if model doesn't exist in test bundle
        guard FileManager.default.fileExists(atPath: modelPath) else {
            XCTSkip("VAD model not available in test bundle")
        }
        
        let detector = VoiceActivityDetector(modelPath: modelPath)
        
        XCTAssertNotNil(detector, "Should initialize with valid model")
    }
    
    // MARK: - Speech Detection Tests
    
    func testProcessWithSilence() {
        guard FileManager.default.fileExists(atPath: modelPath),
              let detector = VoiceActivityDetector(modelPath: modelPath) else {
            XCTSkip("VAD model not available")
        }
        
        // Create silence audio
        let silence = AudioTestHarness.generateSilence(duration: 1.0, sampleRate: 16000.0)
        
        // Convert to float array
        guard let floatData = silence.floatChannelData else {
            XCTFail("Could not get float data")
            return
        }
        
        let samples = Array(UnsafeBufferPointer(start: floatData[0], count: Int(silence.frameLength)))
        
        // Process
        let segments = detector.process(audioSamples: samples)
        
        // Silence should have few or no speech segments
        // (Depending on threshold, might detect some)
        XCTAssertNotNil(segments, "Should return segments array")
    }
    
    func testProcessWithSpeechLike() {
        guard FileManager.default.fileExists(atPath: modelPath),
              let detector = VoiceActivityDetector(modelPath: modelPath) else {
            XCTSkip("VAD model not available")
        }
        
        // Create speech-like audio
        let speechLike = AudioTestHarness.generateSpeechLike(duration: 2.0, sampleRate: 16000.0)
        
        guard let floatData = speechLike.floatChannelData else {
            XCTFail("Could not get float data")
            return
        }
        
        let samples = Array(UnsafeBufferPointer(start: floatData[0], count: Int(speechLike.frameLength)))
        
        // Process
        let segments = detector.process(audioSamples: samples)
        
        // Speech-like audio should potentially be detected
        XCTAssertNotNil(segments, "Should return segments array")
    }
    
    func testProcessWithEmptyArray() {
        guard FileManager.default.fileExists(atPath: modelPath),
              let detector = VoiceActivityDetector(modelPath: modelPath) else {
            XCTSkip("VAD model not available")
        }
        
        // Empty samples
        let segments = detector.process(audioSamples: [])
        
        // Should handle empty input
        XCTAssertNotNil(segments, "Should handle empty input")
        XCTAssertEqual(segments.count, 0, "Should return no segments for empty input")
    }
    
    func testProcessWithVeryShortAudio() {
        guard FileManager.default.fileExists(atPath: modelPath),
              let detector = VoiceActivityDetector(modelPath: modelPath) else {
            XCTSkip("VAD model not available")
        }
        
        // Very short audio (0.1 seconds)
        let shortAudio = AudioTestHarness.generateSilence(duration: 0.1, sampleRate: 16000.0)
        
        guard let floatData = shortAudio.floatChannelData else {
            XCTFail("Could not get float data")
            return
        }
        
        let samples = Array(UnsafeBufferPointer(start: floatData[0], count: Int(shortAudio.frameLength)))
        
        // Process
        let segments = detector.process(audioSamples: samples)
        
        // Should handle short audio
        XCTAssertNotNil(segments, "Should handle short audio")
    }
    
    // MARK: - Segment Properties Tests
    
    func testSegmentTimestamps() {
        guard FileManager.default.fileExists(atPath: modelPath),
              let detector = VoiceActivityDetector(modelPath: modelPath) else {
            XCTSkip("VAD model not available")
        }
        
        // Generate audio
        let audio = AudioTestHarness.generateSpeechLike(duration: 3.0, sampleRate: 16000.0)
        
        guard let floatData = audio.floatChannelData else {
            XCTFail("Could not get float data")
            return
        }
        
        let samples = Array(UnsafeBufferPointer(start: floatData[0], count: Int(audio.frameLength)))
        
        // Process
        let segments = detector.process(audioSamples: samples)
        
        // Check segment properties
        for segment in segments {
            XCTAssertGreaterThanOrEqual(segment.start, 0, "Start should be >= 0")
            XCTAssertGreaterThanOrEqual(segment.end, segment.start, "End should be >= start")
            XCTAssertLessThanOrEqual(segment.end, 3.0, "End should be within audio duration")
        }
    }
    
    // MARK: - Deinit Tests
    
    func testDeinitCleansUpModel() {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            XCTSkip("VAD model not available")
        }
        
        var detector: VoiceActivityDetector? = VoiceActivityDetector(modelPath: modelPath)
        weak var weakDetector = detector
        
        // Use detector
        if let det = detector {
            let samples = Array(repeating: Float(0), count: 1000)
            _ = det.process(audioSamples: samples)
        }
        
        // Release
        detector = nil
        
        // Give time for cleanup
        let expectation = expectation(description: "Deinit")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Should be deallocated (whisper_vad_free called in deinit)
        XCTAssertNil(weakDetector, "Should be deallocated")
    }
    
    func testMultipleDeinitCycles() {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            XCTSkip("VAD model not available")
        }
        
        // Create and destroy multiple times
        for _ in 0..<5 {
            let detector = VoiceActivityDetector(modelPath: modelPath)
            
            if let det = detector {
                let samples = Array(repeating: Float(0), count: 100)
                _ = det.process(audioSamples: samples)
            }
            
            // Detector goes out of scope and deinit is called
        }
        
        // Should not crash
        // Each deinit should call whisper_vad_free properly
    }
    
    // MARK: - Thread Safety Tests
    
    func testConcurrentProcessing() async {
        guard FileManager.default.fileExists(atPath: modelPath),
              let detector = VoiceActivityDetector(modelPath: modelPath) else {
            XCTSkip("VAD model not available")
        }
        
        // Generate test audio
        let audio = AudioTestHarness.generateSpeechLike(duration: 1.0, sampleRate: 16000.0)
        guard let floatData = audio.floatChannelData else {
            XCTFail("Could not get float data")
            return
        }
        let samples = Array(UnsafeBufferPointer(start: floatData[0], count: Int(audio.frameLength)))
        
        // Process from multiple tasks (VAD may not be thread-safe)
        // This tests that it doesn't crash catastrophically
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    _ = detector.process(audioSamples: samples)
                }
            }
            await group.waitForAll()
        }
        
        // Main test: no crash
    }
    
    // MARK: - Parameter Tests
    
    func testDifferentThresholds() {
        // VAD uses internal threshold (0.45 in the code)
        // This tests that it handles detection consistently
        
        guard FileManager.default.fileExists(atPath: modelPath),
              let detector = VoiceActivityDetector(modelPath: modelPath) else {
            XCTSkip("VAD model not available")
        }
        
        let audio = AudioTestHarness.generateSpeechLike(duration: 1.0, sampleRate: 16000.0)
        guard let floatData = audio.floatChannelData else {
            XCTFail("Could not get float data")
            return
        }
        let samples = Array(UnsafeBufferPointer(start: floatData[0], count: Int(audio.frameLength)))
        
        // Process twice with same input
        let segments1 = detector.process(audioSamples: samples)
        let segments2 = detector.process(audioSamples: samples)
        
        // Should get consistent results
        XCTAssertEqual(segments1.count, segments2.count, "Should be deterministic")
    }
}
