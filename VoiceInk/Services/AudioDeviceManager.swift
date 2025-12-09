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
    case systemDefault = "System Default"
    case custom = "Custom Device"
    case prioritized = "Prioritized"
}

enum AudioChannelMode: String, CaseIterable, Codable {
    case mono = "Mono (1 channel)"
    case stereo = "Stereo (2 channels)"
    case deviceMaximum = "Device Maximum"
    case custom = "Custom"

    var channelCount: Int? {
        switch self {
        case .mono: return 1
        case .stereo: return 2
        case .deviceMaximum, .custom: return nil  // Determined dynamically
        }
    }
}

class AudioDeviceManager: ObservableObject {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "AudioDeviceManager")
    @Published var availableDevices: [(id: AudioDeviceID, uid: String, name: String)] = []
    @Published var selectedDeviceID: AudioDeviceID?
    @Published var inputMode: AudioInputMode = .systemDefault
    @Published var prioritizedDevices: [PrioritizedDevice] = []
    @Published var currentDeviceMaxChannels: UInt32 = 1
    var fallbackDeviceID: AudioDeviceID?

    var isRecordingActive: Bool = false

    static let shared = AudioDeviceManager()

    init() {
        setupFallbackDevice()
        loadPrioritizedDevices()
        loadAvailableDevices { [weak self] in
            self?.initializeSelectedDevice()
        }
        
        if let savedMode = UserDefaults.standard.audioInputModeRawValue,
           let mode = AudioInputMode(rawValue: savedMode) {
            inputMode = mode
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
                updateCurrentDeviceChannels()
                logger.info("Loaded saved device UID: \(savedUID), mapped to ID: \(device.id)")
                if let name = getDeviceName(deviceID: device.id) {
                    logger.info("Using saved device: \(name)")
                }
            } else {
                logger.warning("Saved device UID \(savedUID) is no longer available")
                UserDefaults.standard.removeObject(forKey: UserDefaults.Keys.selectedAudioDeviceUID)
                fallbackToDefaultDevice()
            }
        } else {
            fallbackToDefaultDevice()
        }
    }
    
    private func isDeviceAvailable(_ deviceID: AudioDeviceID) -> Bool {
        return availableDevices.contains { $0.id == deviceID }
    }
    
    private func fallbackToDefaultDevice() {
        logger.info("Temporarily falling back to system default input device – user preference remains intact.")

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
            if let currentID = self.selectedDeviceID, !devices.contains(where: { $0.id == currentID }) {
                self.logger.warning("Currently selected device is no longer available")
                self.fallbackToDefaultDevice()
            }
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

        let bufferCount = Int(bufferList.pointee.mNumberBuffers)
        return bufferCount > 0
    }

    func getMaxChannelsForDevice(deviceID: AudioDeviceID) -> UInt32 {
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

        guard result == noErr else {
            logger.error("Error getting property size for device \(deviceID): \(result)")
            return 1
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

        guard result == noErr else {
            logger.error("Error getting stream configuration for device \(deviceID): \(result)")
            return 1
        }

        var totalChannels: UInt32 = 0
        let bufferCount = Int(bufferList.pointee.mNumberBuffers)

        for i in 0..<bufferCount {
            let audioBuffer = withUnsafePointer(to: &bufferList.pointee.mBuffers) {
                UnsafeBufferPointer(start: $0, count: bufferCount)[i]
            }
            totalChannels += audioBuffer.mNumberChannels
        }

        logger.info("Device \(deviceID) has \(totalChannels) input channels")
        return max(totalChannels, 1)  // At least 1 channel
    }

    func updateCurrentDeviceChannels() {
        guard let deviceID = selectedDeviceID else {
            currentDeviceMaxChannels = 1
            return
        }
        currentDeviceMaxChannels = getMaxChannelsForDevice(deviceID: deviceID)
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
                self.updateCurrentDeviceChannels()
                self.logger.info("Device selection saved with UID: \(uid)")
                self.notifyDeviceChange()
            }
        } else {
            logger.error("Attempted to select unavailable device: \(id)")
            fallbackToDefaultDevice()
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
                self.updateCurrentDeviceChannels()
                self.notifyDeviceChange()
            }
        } else {
            logger.error("Attempted to select unavailable device: \(id)")
            fallbackToDefaultDevice()
        }
    }
    
    func selectInputMode(_ mode: AudioInputMode) {
        inputMode = mode
        UserDefaults.standard.audioInputModeRawValue = mode.rawValue
        
        if mode == .systemDefault {
            selectedDeviceID = nil
            UserDefaults.standard.removeObject(forKey: UserDefaults.Keys.selectedAudioDeviceUID)
        } else if selectedDeviceID == nil {
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
        case .systemDefault:
            return fallbackDeviceID ?? 0
        case .custom:
            if let id = selectedDeviceID, isDeviceAvailable(id) {
                return id
            } else {
                return fallbackDeviceID ?? 0
            }
        case .prioritized:
            let sortedDevices = prioritizedDevices.sorted { $0.priority < $1.priority }
            for device in sortedDevices {
                if let available = availableDevices.first(where: { $0.uid == device.id }) {
                    return available.id
                }
            }
            return fallbackDeviceID ?? 0
        }
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
                
                do {
                    try AudioDeviceConfiguration.setDefaultInputDevice(availableDevice.id)
                } catch {
                    logger.error("Failed to set prioritized device: \(error.localizedDescription)")
                    continue
                }
                notifyDeviceChange()
                return
            }
        }
        
        fallbackToDefaultDevice()
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
                self.fallbackToDefaultDevice()
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
        if !isRecordingActive {
            NotificationCenter.default.post(name: NSNotification.Name("AudioDeviceChanged"), object: nil)
        }
    }
} 
