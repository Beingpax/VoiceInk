import Foundation
import CoreAudio
@testable import VoiceInk

/// Mock audio device for testing
@available(macOS 14.0, *)
final class MockAudioDevice {
    let id: AudioDeviceID
    let uid: String
    let name: String
    var isAvailable: Bool = true
    var sampleRate: Double = 16000.0
    
    init(id: AudioDeviceID, uid: String, name: String) {
        self.id = id
        self.uid = uid
        self.name = name
    }
    
    static func createMockDevice(name: String = "Mock Microphone") -> MockAudioDevice {
        let id = AudioDeviceID(arc4random_uniform(10000) + 20000)
        let uid = UUID().uuidString
        return MockAudioDevice(id: id, uid: uid, name: name)
    }
    
    static func createMockDevices(count: Int) -> [MockAudioDevice] {
        (0..<count).map { index in
            createMockDevice(name: "Mock Microphone \(index + 1)")
        }
    }
}

/// Mock audio device manager for testing
@available(macOS 14.0, *)
@MainActor
final class MockAudioDeviceManager: ObservableObject {
    @Published var availableDevices: [(id: AudioDeviceID, uid: String, name: String)] = []
    @Published var selectedDeviceID: AudioDeviceID?
    @Published var inputMode: AudioInputMode = .systemDefault
    @Published var prioritizedDevices: [PrioritizedDevice] = []
    var fallbackDeviceID: AudioDeviceID?
    var isRecordingActive: Bool = false
    
    private var mockDevices: [MockAudioDevice] = []
    
    init() {
        // Start with a default device
        let defaultDevice = MockAudioDevice.createMockDevice(name: "Default Microphone")
        mockDevices = [defaultDevice]
        fallbackDeviceID = defaultDevice.id
        updateAvailableDevices()
    }
    
    func addDevice(_ device: MockAudioDevice) {
        mockDevices.append(device)
        updateAvailableDevices()
    }
    
    func removeDevice(_ device: MockAudioDevice) {
        mockDevices.removeAll { $0.id == device.id }
        updateAvailableDevices()
    }
    
    func simulateDeviceDisconnect(_ deviceID: AudioDeviceID) {
        if let device = mockDevices.first(where: { $0.id == deviceID }) {
            device.isAvailable = false
            updateAvailableDevices()
        }
    }
    
    func simulateDeviceReconnect(_ deviceID: AudioDeviceID) {
        if let device = mockDevices.first(where: { $0.id == deviceID }) {
            device.isAvailable = true
            updateAvailableDevices()
        }
    }
    
    func getCurrentDevice() -> AudioDeviceID {
        if let selectedID = selectedDeviceID, availableDevices.contains(where: { $0.id == selectedID }) {
            return selectedID
        }
        return fallbackDeviceID ?? 0
    }
    
    func selectDevice(id: AudioDeviceID) {
        selectedDeviceID = id
    }
    
    private func updateAvailableDevices() {
        availableDevices = mockDevices
            .filter { $0.isAvailable }
            .map { ($0.id, $0.uid, $0.name) }
    }
}
