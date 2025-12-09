import Foundation
import CoreAudio
import AVFoundation
import os

struct PrioritizedDevice: Codable, Identifiable {
    let id: String
    let name: String
    let priority: Int
}

enum AudioInputMode: String, CaseIterable {
    case custom = "Custom Device"
    case prioritized = "Prioritized"
}

class AudioDeviceManager: ObservableObject {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "AudioDeviceManager")
    @Published var availableDevices: [(id: AudioDeviceID, uid: String, name: String)] = []
    @Published var selectedDeviceID: AudioDeviceID?
    @Published var inputMode: AudioInputMode = .custom
    @Published var prioritizedDevices: [PrioritizedDevice] = []
    var fallbackDeviceID: AudioDeviceID?
    
    var isRecordingActive: Bool = false
    
    static let shared = AudioDeviceManager()

    init() {
        setupFallbackDevice()
        loadPrioritizedDevices()
        loadAvailableDevices { [weak self] in
            self?.initializeSelectedDevice()
        }

        // Migrate users from deprecated systemDefault mode
        if let savedMode = UserDefaults.standard.audioInputModeRawValue {
            if savedMode == "System Default" {
                inputMode = .custom
                UserDefaults.standard.audioInputModeRawValue = AudioInputMode.custom.rawValue
                logger.info("Migrated from deprecated 'System Default' mode to 'Custom' mode")
            } else if let mode = AudioInputMode(rawValue: savedMode) {
                inputMode = mode
            }
        }

        setupDeviceChangeNotifications()
    }
    
    func setupFallbackDevice() {
        let deviceID: AudioDeviceID? = getDeviceProperty(
            deviceID: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDefaultInputDevice
        )
        
        if let deviceID = deviceID {
            fallbackDeviceID = deviceID
            if let name = getDeviceName(deviceID: deviceID) {
                logger.info("Fallback device set to: \(name) (ID: \(deviceID))")
            }
        } else {
            logger.error("Failed to get fallback device")
        }
    }
    
    private func initializeSelectedDevice() {
        if inputMode == .prioritized {
            selectHighestPriorityAvailableDevice()
            return
        }
        
        if let savedUID = UserDefaults.standard.selectedAudioDeviceUID {
            if let device = availableDevices.first(where: { $0.uid == savedUID }) {
                selectedDeviceID = device.id
                logger.info("Loaded saved device UID: \(savedUID), mapped to ID: \(device.id)")
                if let name = getDeviceName(deviceID: device.id) {
                    logger.info("Using saved device: \(name)")
                }
            } else {
                logger.warning("Saved device UID \(savedUID) is no longer available")
                UserDefaults.standard.removeObject(forKey: UserDefaults.Keys.selectedAudioDeviceUID)
                fallbackToAvailableDevice()
            }
        } else {
            fallbackToAvailableDevice()
        }
    }
    
    private func isDeviceAvailable(_ deviceID: AudioDeviceID) -> Bool {
        return availableDevices.contains { $0.id == deviceID }
    }
    
    private func fallbackToAvailableDevice() {
        logger.info("Selected device unavailable, falling back to available device – user preference remains intact.")

        if let currentID = selectedDeviceID, !isDeviceAvailable(currentID) {
            selectedDeviceID = nil
        }

        notifyDeviceChange()
    }
    
    func loadAvailableDevices(completion: (() -> Void)? = nil) {
        logger.info("Loading available audio devices...")
        var propertySize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var result = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize
        )
        
        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        logger.info("Found \(deviceCount) total audio devices")
        
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        result = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceIDs
        )
        
        if result != noErr {
            logger.error("Error getting audio devices: \(result)")
            return
        }
        
        let devices = deviceIDs.compactMap { deviceID -> (id: AudioDeviceID, uid: String, name: String)? in
            guard let name = getDeviceName(deviceID: deviceID),
                  let uid = getDeviceUID(deviceID: deviceID),
                  isValidInputDevice(deviceID: deviceID) else {
                return nil
            }
            return (id: deviceID, uid: uid, name: name)
        }
        
        logger.info("Found \(devices.count) input devices")
        devices.forEach { device in
            logger.info("Available device: \(device.name) (ID: \(device.id))")
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.availableDevices = devices.map { ($0.id, $0.uid, $0.name) }
            completion?()
        }
    }
    
    func getDeviceName(deviceID: AudioDeviceID) -> String? {
        let name: CFString? = getDeviceProperty(deviceID: deviceID,
                                              selector: kAudioDevicePropertyDeviceNameCFString)
        return name as String?
    }
    
    private func isValidInputDevice(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var propertySize: UInt32 = 0
        var result = AudioObjectGetPropertyDataSize(
            deviceID,
            &address,
            0,
            nil,
            &propertySize
        )

        if result != noErr {
            logger.error("Error checking input capability for device \(deviceID): \(result)")
            return false
        }

        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(propertySize))
        defer { bufferList.deallocate() }

        result = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            bufferList
        )

        if result != noErr {
            logger.error("Error getting stream configuration for device \(deviceID): \(result)")
            return false
        }

        var totalChannels: UInt32 = 0
        let bufferListPointer = UnsafeMutableAudioBufferListPointer(bufferList)
        for buffer in bufferListPointer {
            totalChannels += buffer.mNumberChannels
        }

        return totalChannels > 0
    }

    func selectDevice(id: AudioDeviceID) {
        logger.info("Selecting device with ID: \(id)")
        if let name = getDeviceName(deviceID: id) {
            logger.info("Selected device name: \(name)")
        }

        if let deviceToSelect = availableDevices.first(where: { $0.id == id }) {
            let uid = deviceToSelect.uid
            DispatchQueue.main.async {
                self.selectedDeviceID = id
                UserDefaults.standard.selectedAudioDeviceUID = uid
                self.logger.info("Device selection saved with UID: \(uid)")
                self.notifyDeviceChange()
            }
        } else {
            logger.error("Attempted to select unavailable device: \(id)")
            fallbackToAvailableDevice()
        }
    }

    func selectDeviceAndSwitchToCustomMode(id: AudioDeviceID) {
        if let deviceToSelect = availableDevices.first(where: { $0.id == id }) {
            let uid = deviceToSelect.uid
            DispatchQueue.main.async {
                self.inputMode = .custom
                self.selectedDeviceID = id
                UserDefaults.standard.audioInputModeRawValue = AudioInputMode.custom.rawValue
                UserDefaults.standard.selectedAudioDeviceUID = uid
                self.notifyDeviceChange()
            }
        } else {
            logger.error("Attempted to select unavailable device: \(id)")
            fallbackToAvailableDevice()
        }
    }
    
    func selectInputMode(_ mode: AudioInputMode) {
        inputMode = mode
        UserDefaults.standard.audioInputModeRawValue = mode.rawValue

        if selectedDeviceID == nil {
            if inputMode == .custom {
                if let firstDevice = availableDevices.first {
                    selectDevice(id: firstDevice.id)
                }
            } else if inputMode == .prioritized {
                selectHighestPriorityAvailableDevice()
            }
        }

        notifyDeviceChange()
    }
    
    func getCurrentDevice() -> AudioDeviceID {
        switch inputMode {
        case .custom:
            if let id = selectedDeviceID, isDeviceAvailable(id) {
                return id
            } else {
                return getFallbackDevice(excluding: selectedDeviceID) ?? 0
            }
        case .prioritized:
            let sortedDevices = prioritizedDevices.sorted { $0.priority < $1.priority }
            for device in sortedDevices {
                if let available = availableDevices.first(where: { $0.uid == device.id }) {
                    return available.id
                }
            }
            return getFallbackDevice(excluding: nil) ?? 0
        }
    }

    // Finds fallback device, preferring built-in mic, excluding specified device
    func getFallbackDevice(excluding excludeDeviceID: AudioDeviceID?) -> AudioDeviceID? {
        let candidates = availableDevices.filter { device in
            if let excludeID = excludeDeviceID {
                return device.id != excludeID
            }
            return true
        }

        guard !candidates.isEmpty else {
            logger.warning("No available audio input devices found")
            return nil
        }

        // Prefer built-in microphone
        if let builtin = candidates.first(where: { device in
            device.name.lowercased().contains("built-in") ||
            device.name.lowercased().contains("internal")
        }) {
            logger.info("Found built-in microphone: \(builtin.name)")
            return builtin.id
        }

        // Return first available device
        if let firstDevice = candidates.first {
            logger.info("Using first available device: \(firstDevice.name)")
            return firstDevice.id
        }

        return nil
    }

    private func loadPrioritizedDevices() {
        if let data = UserDefaults.standard.prioritizedDevicesData,
           let devices = try? JSONDecoder().decode([PrioritizedDevice].self, from: data) {
            prioritizedDevices = devices
            logger.info("Loaded \(devices.count) prioritized devices")
        }
    }
    
    func savePrioritizedDevices() {
        if let data = try? JSONEncoder().encode(prioritizedDevices) {
            UserDefaults.standard.prioritizedDevicesData = data
            logger.info("Saved \(self.prioritizedDevices.count) prioritized devices")
        }
    }
    
    func addPrioritizedDevice(uid: String, name: String) {
        guard !prioritizedDevices.contains(where: { $0.id == uid }) else { return }
        let nextPriority = (prioritizedDevices.map { $0.priority }.max() ?? -1) + 1
        let device = PrioritizedDevice(id: uid, name: name, priority: nextPriority)
        prioritizedDevices.append(device)
        savePrioritizedDevices()
    }
    
    func removePrioritizedDevice(id: String) {
        let wasSelected = selectedDeviceID == availableDevices.first(where: { $0.uid == id })?.id
        prioritizedDevices.removeAll { $0.id == id }
        
        let updatedDevices = prioritizedDevices.enumerated().map { index, device in
            PrioritizedDevice(id: device.id, name: device.name, priority: index)
        }
        
        prioritizedDevices = updatedDevices
        savePrioritizedDevices()
        
        if wasSelected && inputMode == .prioritized {
            selectHighestPriorityAvailableDevice()
        }
    }
    
    func updatePriorities(devices: [PrioritizedDevice]) {
        prioritizedDevices = devices
        savePrioritizedDevices()
        
        if inputMode == .prioritized {
            selectHighestPriorityAvailableDevice()
        }
        
        notifyDeviceChange()
    }
    
    private func selectHighestPriorityAvailableDevice() {
        let sortedDevices = prioritizedDevices.sorted { $0.priority < $1.priority }

        for device in sortedDevices {
            if let availableDevice = availableDevices.first(where: { $0.uid == device.id }) {
                selectedDeviceID = availableDevice.id
                logger.info("Selected prioritized device: \(device.name) (Priority: \(device.priority))")

                notifyDeviceChange()
                return
            }
        }

        fallbackToAvailableDevice()
    }
    
    private func setupDeviceChangeNotifications() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
        
        let status = AudioObjectAddPropertyListener(
            systemObjectID,
            &address,
            { (_, _, _, userData) -> OSStatus in
                let manager = Unmanaged<AudioDeviceManager>.fromOpaque(userData!).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.handleDeviceListChange()
                }
                return noErr
            },
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        
        if status != noErr {
            logger.error("Failed to add device change listener: \(status)")
        } else {
            logger.info("Successfully added device change listener")
        }
    }
    
    private func handleDeviceListChange() {
        logger.info("Device list change detected")
        loadAvailableDevices { [weak self] in
            guard let self = self else { return }

            if self.inputMode == .prioritized {
                self.selectHighestPriorityAvailableDevice()
            } else if self.inputMode == .custom,
                      let currentID = self.selectedDeviceID,
                      !self.isDeviceAvailable(currentID) {
                if let fallbackID = self.getFallbackDevice(excluding: nil),
                   let deviceToSelect = self.availableDevices.first(where: { $0.id == fallbackID }) {
                    self.logger.info("Selected custom device unavailable, switching to fallback device: \(deviceToSelect.name)")

                    self.selectedDeviceID = fallbackID
                    UserDefaults.standard.selectedAudioDeviceUID = deviceToSelect.uid
                    self.objectWillChange.send()
                    self.notifyDeviceChange()

                    Task { @MainActor in
                        NotificationManager.shared.showNotification(
                            title: "Switched to \(deviceToSelect.name)",
                            type: .info
                        )
                    }
                } else {
                    self.logger.warning("No fallback device available")
                    self.fallbackToAvailableDevice()
                }
            }
        }
    }
    
    private func getDeviceUID(deviceID: AudioDeviceID) -> String? {
        let uid: CFString? = getDeviceProperty(deviceID: deviceID,
                                             selector: kAudioDevicePropertyDeviceUID)
        return uid as String?
    }
    
    deinit {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            { (_, _, _, userData) -> OSStatus in
                return noErr
            },
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
    }
    
    private func createPropertyAddress(selector: AudioObjectPropertySelector,
                                    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                                    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        return AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
    }
    
    private func getDeviceProperty<T>(deviceID: AudioDeviceID,
                                    selector: AudioObjectPropertySelector,
                                    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> T? {
        guard deviceID != 0 else { return nil }
        
        var address = createPropertyAddress(selector: selector, scope: scope)
        var propertySize = UInt32(MemoryLayout<T>.size)
        var property: T? = nil
        
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &property
        )
        
        if status != noErr {
            logger.error("Failed to get device property \(selector) for device \(deviceID): \(status)")
            return nil
        }
        
        return property
    }
    
    private func notifyDeviceChange() {
        NotificationCenter.default.post(name: NSNotification.Name("AudioDeviceChanged"), object: nil)
    }
} 
