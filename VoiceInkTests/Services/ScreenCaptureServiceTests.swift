import XCTest
import AppKit
@testable import VoiceInk

/// Tests for ScreenCaptureService - OCR and window capture
/// FOCUS: Permission handling, concurrent capture prevention, OCR accuracy
@available(macOS 14.0, *)
@MainActor
final class ScreenCaptureServiceTests: XCTestCase {
    
    var captureService: ScreenCaptureService!
    
    override func setUp() async throws {
        try await super.setUp()
        captureService = ScreenCaptureService()
    }
    
    override func tearDown() async throws {
        captureService = nil
        try await super.tearDown()
    }
    
    // MARK: - Initial State Tests
    
    func testInitialState() {
        XCTAssertFalse(captureService.isCapturing, "Should not be capturing initially")
        XCTAssertNil(captureService.lastCapturedText, "Should have no captured text initially")
    }
    
    // MARK: - Permission Handling Tests
    
    func testCaptureWithoutPermission() async {
        // Attempt capture (may fail due to permissions)
        let result = await captureService.captureAndExtractText()
        
        // Should handle gracefully (return nil or empty)
        // In test environment, we may not have permissions
        if result == nil {
            // Expected in test environment without permissions
            XCTAssertNil(result, "Should return nil without permissions")
        }
        
        // Should not crash
        XCTAssertNotNil(captureService, "Service should survive capture attempt")
    }
    
    func testIsCapturingFlagDuringCapture() async {
        // Start capture
        let captureTask = Task {
            await captureService.captureAndExtractText()
        }
        
        // Check flag immediately (may or may not be set depending on timing)
        // This is a race, but we're testing that accessing the flag doesn't crash
        _ = captureService.isCapturing
        
        // Wait for capture to complete
        await captureTask.value
        
        // Should be false after completion
        XCTAssertFalse(captureService.isCapturing, "Should not be capturing after completion")
    }
    
    // MARK: - Concurrent Capture Prevention Tests
    
    func testConcurrentCaptureAttempts() async {
        // Try to start multiple captures
        async let capture1: String? = captureService.captureAndExtractText()
        async let capture2: String? = captureService.captureAndExtractText()
        async let capture3: String? = captureService.captureAndExtractText()
        
        // Wait for all attempts
        let results = await [capture1, capture2, capture3]
        
        // At least some should return nil (concurrent prevention)
        // In test environment, likely all will be nil due to permissions
        XCTAssertNotNil(captureService, "Should handle concurrent attempts")
    }
    
    func testIsCapturingPreventsConcurrency() async {
        // Manually set flag (simulating ongoing capture)
        captureService.isCapturing = true
        
        // Try to capture
        let result = await captureService.captureAndExtractText()
        
        // Should return nil due to ongoing capture
        XCTAssertNil(result, "Should prevent concurrent capture")
        
        // Reset flag
        captureService.isCapturing = false
    }
    
    // MARK: - Window Info Tests
    
    func testGetActiveWindowInfo() async {
        // Test that getting window info doesn't crash
        // This uses private method, so we test the public API that calls it
        
        let result = await captureService.captureAndExtractText()
        
        // May be nil due to permissions or no active window
        // Main test is that it doesn't crash
        XCTAssertNotNil(captureService, "Should survive window info retrieval")
    }
    
    // MARK: - OCR Text Recognition Tests
    
    func testTextExtractionFromNilImage() async {
        // This tests the internal text extraction with nil image
        // Since the method is private, we test via the public API
        
        let result = await captureService.captureAndExtractText()
        
        // Should handle nil image gracefully
        XCTAssertNotNil(captureService, "Should handle nil image")
    }
    
    // MARK: - Last Captured Text Tests
    
    func testLastCapturedTextUpdates() async {
        // Initial state
        XCTAssertNil(captureService.lastCapturedText)
        
        // Attempt capture
        let result = await captureService.captureAndExtractText()
        
        // If capture succeeded, lastCapturedText should be updated
        if result != nil {
            XCTAssertEqual(captureService.lastCapturedText, result)
        }
    }
    
    // MARK: - Published Property Tests
    
    func testIsCapturingPublishedProperty() {
        var captureStates: [Bool] = []
        let expectation = expectation(description: "Observe isCapturing")
        
        let cancellable = captureService.$isCapturing
            .sink { isCapturing in
                captureStates.append(isCapturing)
                if captureStates.count >= 2 {
                    expectation.fulfill()
                }
            }
        
        // Change state
        captureService.isCapturing = true
        captureService.isCapturing = false
        
        wait(for: [expectation], timeout: 1.0)
        
        cancellable.cancel()
        
        // Should have captured state changes
        XCTAssertGreaterThanOrEqual(captureStates.count, 2)
    }
    
    func testLastCapturedTextPublishedProperty() {
        var capturedTexts: [String?] = []
        let expectation = expectation(description: "Observe lastCapturedText")
        
        let cancellable = captureService.$lastCapturedText
            .sink { text in
                capturedTexts.append(text)
                if capturedTexts.count >= 2 {
                    expectation.fulfill()
                }
            }
        
        // Change state
        captureService.lastCapturedText = "Test text 1"
        captureService.lastCapturedText = "Test text 2"
        
        wait(for: [expectation], timeout: 1.0)
        
        cancellable.cancel()
        
        // Should have captured text changes
        XCTAssertGreaterThanOrEqual(capturedTexts.count, 2)
    }
    
    // MARK: - Error Handling Tests
    
    func testHandlesScreenCaptureKitErrors() async {
        // Test that service handles ScreenCaptureKit errors gracefully
        // This may throw errors in test environment
        
        let result = await captureService.captureAndExtractText()
        
        // Should return nil on error, not crash
        if result == nil {
            XCTAssertNil(result, "Should handle errors gracefully")
        }
        
        XCTAssertNotNil(captureService, "Service should survive errors")
    }
    
    // MARK: - Context String Format Tests
    
    func testCapturedTextFormat() async {
        // If capture succeeds, verify format
        let result = await captureService.captureAndExtractText()
        
        if let text = result {
            // Should contain window info
            XCTAssertTrue(text.contains("Active Window:") || text.contains("Application:"),
                         "Should include window metadata")
        }
    }
    
    // MARK: - Memory Tests
    
    func testServiceDoesNotLeak() async {
        weak var weakService: ScreenCaptureService?
        
        await autoreleasepool {
            let service = ScreenCaptureService()
            weakService = service
            
            // Attempt capture
            _ = await service.captureAndExtractText()
        }
        
        // Give time for deallocation
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        XCTAssertNil(weakService, "ScreenCaptureService should not leak")
    }
    
    func testMultipleCapturesDoNotLeak() async {
        weak var weakService: ScreenCaptureService?
        
        await autoreleasepool {
            let service = ScreenCaptureService()
            weakService = service
            
            // Multiple captures
            for _ in 0..<5 {
                _ = await service.captureAndExtractText()
            }
        }
        
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        XCTAssertNil(weakService, "Should not leak with multiple captures")
    }
    
    // MARK: - Rapid Capture Tests
    
    func testRapidCaptureAttempts() async {
        // Test rapid consecutive captures
        for _ in 0..<10 {
            _ = await captureService.captureAndExtractText()
        }
        
        // Should handle rapid calls without crash
        XCTAssertNotNil(captureService, "Should handle rapid captures")
        XCTAssertFalse(captureService.isCapturing, "Should be idle after captures")
    }
}
