import XCTest
import CoreAudio
@testable import VoiceInk

/// Tests for AudioDeviceManager - critical for device switching stability
@available(macOS 14.0, *)
@MainActor
final class AudioDeviceManagerTests: XCTestCase {
    
    var deviceManager: AudioDeviceManager!
    
    override func setUp() async throws {
        try await super.setUp()
        deviceManager = AudioDeviceManager()
        
        // Give time for initial device enumeration
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
    }
    
    override func tearDown() async throws {
        deviceManager = nil
        try await super.tearDown()
    }
    
    // MARK: - Device Enumeration Tests
    
    func testDeviceEnumerationWithNoDevices() {
        // Test that manager handles empty device list gracefully
        // This simulates the case where no audio devices are available
        
        // Even with no user-added devices, there should be a fallback
        XCTAssertNotNil(deviceManager.fallbackDeviceID, "Should have fallback device")
    }
    
    func testAvailableDevicesLoaded() {
        // Verify that devices were loaded during initialization
        // In a real Mac environment, there should be at least one device
        
        XCTAssertNotNil(deviceManager.availableDevices, "Available devices should be initialized")
        
        // If we're on a Mac with audio hardware, we should have devices
        if deviceManager.availableDevices.isEmpty {
            XCTAssertNotNil(deviceManager.fallbackDeviceID, "Should have fallback even with no devices")
        }
    }
    
    func testLoadAvailableDevicesCompletes() async {
        // Test that loading devices doesn't crash or hang
        let expectation = expectation(description: "Devices loaded")
        
        deviceManager.loadAvailableDevices {
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 5.0)
        XCTAssertNotNil(deviceManager, "Device manager should survive device loading")
    }
    
    func testDevicePropertiesAreValid() {
        // Verify that all loaded devices have valid properties
        for device in deviceManager.availableDevices {
            XCTAssertNotEqual(device.id, 0, "Device ID should not be zero")
            XCTAssertFalse(device.uid.isEmpty, "Device UID should not be empty")
            XCTAssertFalse(device.name.isEmpty, "Device name should not be empty")
        }
    }
    
    // MARK: - Device UID Persistence Tests
    
    func testDeviceUIDPersistence() {
        // Test that device UID is saved and can be retrieved
        guard let firstDevice = deviceManager.availableDevices.first else {
            XCTSkip("No devices available for testing")
        }
        
        // Save device UID
        UserDefaults.standard.set(firstDevice.uid, forKey: "selectedAudioDeviceUID")
        
        // Create new manager instance
        let newManager = AudioDeviceManager()
        
        // Give time for initialization
        let expectation = expectation(description: "Manager initialized")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Verify device was restored from UID
        if let selectedID = newManager.selectedDeviceID {
            let selectedDevice = newManager.availableDevices.first { $0.id == selectedID }
            XCTAssertEqual(selectedDevice?.uid, firstDevice.uid, "Device should be restored from UID")
        }
        
        // Cleanup
        UserDefaults.standard.removeObject(forKey: "selectedAudioDeviceUID")
    }
    
    func testFallbackToDefaultOnMissingDevice() {
        // Simulate a saved device that no longer exists
        UserDefaults.standard.set("nonexistent-device-uid", forKey: "selectedAudioDeviceUID")
        
        let newManager = AudioDeviceManager()
        
        // Give time for initialization
        let expectation = expectation(description: "Manager initialized")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Should fall back to default device
        XCTAssertNotNil(newManager.fallbackDeviceID, "Should have fallback device")
        
        // Cleanup
        UserDefaults.standard.removeObject(forKey: "selectedAudioDeviceUID")
    }
    
    // MARK: - Prioritized Device Selection Tests
    
    func testPrioritizedDeviceSelection() {
        // Set mode to prioritized
        deviceManager.inputMode = .prioritized
        
        // Add some prioritized devices
        guard let firstDevice = deviceManager.availableDevices.first else {
            XCTSkip("No devices available for testing")
        }
        
        deviceManager.prioritizedDevices = [
            PrioritizedDevice(id: firstDevice.uid, name: firstDevice.name, priority: 1)
        ]
        
        // Trigger selection
        deviceManager.selectHighestPriorityAvailableDevice()
        
        // Should select the prioritized device
        XCTAssertEqual(deviceManager.selectedDeviceID, firstDevice.id)
    }
    
    // MARK: - Device Change Notification Tests
    
    func testDeviceChangeNotification() async {
        // Test that device changes trigger notifications
        let expectation = expectation(description: "Device change notification")
        
        let observer = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AudioDeviceChanged"),
            object: nil,
            queue: .main
        ) { _ in
            expectation.fulfill()
        }
        
        defer {
            NotificationCenter.default.removeObserver(observer)
        }
        
        // Trigger device notification manually (simulating system event)
        deviceManager.notifyDeviceChange()
        
        await fulfillment(of: [expectation], timeout: 2.0)
    }
    
    // MARK: - getCurrentDevice Thread Safety Tests
    
    func testGetCurrentDeviceThreadSafety() async {
        // Test that getCurrentDevice can be called from multiple tasks
        await assertConcurrentExecution(iterations: 100) {
            let deviceID = self.deviceManager.getCurrentDevice()
            XCTAssertNotEqual(deviceID, 0, "Should always return a valid device ID")
        }
    }
    
    func testGetCurrentDeviceConsistency() {
        // Test that getCurrentDevice returns consistent results
        let device1 = deviceManager.getCurrentDevice()
        let device2 = deviceManager.getCurrentDevice()
        
        XCTAssertEqual(device1, device2, "Should return same device when called twice")
    }
    
    // MARK: - isRecordingActive Flag Tests
    
    func testIsRecordingActiveFlagConsistency() {
        // Test flag lifecycle
        XCTAssertFalse(deviceManager.isRecordingActive, "Should start as not recording")
        
        deviceManager.isRecordingActive = true
        XCTAssertTrue(deviceManager.isRecordingActive, "Should be recording")
        
        deviceManager.isRecordingActive = false
        XCTAssertFalse(deviceManager.isRecordingActive, "Should not be recording")
    }
    
    func testRecordingFlagConcurrentAccess() async {
        // Test concurrent access to recording flag
        var results: [Bool] = []
        let resultsLock = NSLock()
        
        await assertConcurrentExecution(iterations: 50) {
            // Toggle flag
            self.deviceManager.isRecordingActive = !self.deviceManager.isRecordingActive
            
            // Read flag
            let value = self.deviceManager.isRecordingActive
            
            resultsLock.lock()
            results.append(value)
            resultsLock.unlock()
        }
        
        // Should have completed without crash
        XCTAssertEqual(results.count, 50, "Should have recorded all flag states")
    }
    
    // MARK: - Property Observer Cleanup Tests
    
    func testPropertyObserverCleanupInDeinit() async {
        var manager: AudioDeviceManager? = AudioDeviceManager()
        weak var weakManager = manager
        
        // Give time for setup
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // Release manager
        manager = nil
        
        // Give time for deinit
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertNil(weakManager, "Manager should be deallocated")
        
        // Post notification - should not crash
        NotificationCenter.default.post(
            name: NSNotification.Name(rawValue: "\(kAudioHardwarePropertyDevices)"),
            object: nil
        )
    }
    
    // MARK: - Audio Device Property Access Tests
    
    func testGetDeviceNameWithValidDevice() {
        guard let firstDevice = deviceManager.availableDevices.first else {
            XCTSkip("No devices available for testing")
        }
        
        if let name = deviceManager.getDeviceName(deviceID: firstDevice.id) {
            XCTAssertFalse(name.isEmpty, "Device name should not be empty")
            XCTAssertEqual(name, firstDevice.name, "Should match stored name")
        } else {
            XCTFail("Should be able to get device name")
        }
    }
    
    func testGetDeviceNameWithInvalidDevice() {
        // Test with invalid device ID
        let invalidDeviceID = AudioDeviceID(99999)
        let name = deviceManager.getDeviceName(deviceID: invalidDeviceID)
        
        // Should handle gracefully (return nil or empty)
        if let name = name {
            XCTAssertTrue(name.isEmpty || name == "Unknown", "Invalid device should have no name or 'Unknown'")
        }
    }
    
    // MARK: - Invalid Device ID Handling Tests
    
    func testHandleInvalidDeviceID() {
        // Test that manager handles zero device ID gracefully
        deviceManager.selectedDeviceID = 0
        
        let currentDevice = deviceManager.getCurrentDevice()
        
        // Should return fallback device
        XCTAssertEqual(currentDevice, deviceManager.fallbackDeviceID ?? 0)
    }
    
    func testSelectNonexistentDevice() {
        // Try to select a device that doesn't exist
        let nonexistentID = AudioDeviceID(88888)
        deviceManager.selectedDeviceID = nonexistentID
        
        // getCurrentDevice should handle this gracefully
        let device = deviceManager.getCurrentDevice()
        XCTAssertNotEqual(device, 0, "Should return valid device even with invalid selection")
    }
    
    // MARK: - Device Availability Checking Tests
    
    func testDeviceAvailabilityCheck() {
        guard let firstDevice = deviceManager.availableDevices.first else {
            XCTSkip("No devices available for testing")
        }
        
        // Device in the list should be available
        let isAvailable = deviceManager.availableDevices.contains { $0.id == firstDevice.id }
        XCTAssertTrue(isAvailable, "Device in list should be available")
    }
    
    // MARK: - Concurrent loadAvailableDevices Tests
    
    func testConcurrentLoadAvailableDevicesCalls() async {
        // Test multiple simultaneous calls to loadAvailableDevices
        let expectations = (0..<5).map { expectation(description: "Load \($0)") }
        
        for expectation in expectations {
            deviceManager.loadAvailableDevices {
                expectation.fulfill()
            }
        }
        
        await fulfillment(of: expectations, timeout: 10.0)
        
        // Should complete all loads without crash
        XCTAssertNotNil(deviceManager, "Manager should survive concurrent loads")
        XCTAssertNotNil(deviceManager.availableDevices, "Devices should be loaded")
    }
    
    // MARK: - Memory Leak Tests
    
    func testDeviceManagerDoesNotLeak() async {
        weak var weakManager: AudioDeviceManager?
        
        await autoreleasepool {
            let manager = AudioDeviceManager()
            weakManager = manager
            
            // Perform some operations
            _ = manager.getCurrentDevice()
            manager.isRecordingActive = true
            manager.isRecordingActive = false
        }
        
        // Give time for deallocation
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
        
        XCTAssertNil(weakManager, "AudioDeviceManager should be deallocated")
    }
    
    func testDeviceManagerWithMultipleOperations() async {
        weak var weakManager: AudioDeviceManager?
        
        await autoreleasepool {
            let manager = AudioDeviceManager()
            weakManager = manager
            
            // Simulate real usage
            for _ in 0..<10 {
                _ = manager.getCurrentDevice()
                manager.loadAvailableDevices { }
                try? await Task.sleep(nanoseconds: 10_000_000) // 0.01s
            }
        }
        
        // Give time for cleanup
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        XCTAssertNil(weakManager, "Manager should not leak with multiple operations")
    }
}
