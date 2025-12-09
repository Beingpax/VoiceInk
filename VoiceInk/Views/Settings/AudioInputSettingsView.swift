import SwiftUI

struct AudioInputSettingsView: View {
    @ObservedObject var audioDeviceManager = AudioDeviceManager.shared
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroSection
                mainContent
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var mainContent: some View {
        VStack(spacing: 40) {
            inputModeSection

            if audioDeviceManager.inputMode == .custom {
                customDeviceSection
            } else if audioDeviceManager.inputMode == .prioritized {
                prioritizedDevicesSection
            }

            recordingConfigurationSection
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 40)
    }
    
    private var heroSection: some View {
        VStack(spacing: 24) {
            Image(systemName: "waveform")
                .font(.system(size: 40))
                .foregroundStyle(.blue)
                .padding(20)
                .background(Circle()
                    .fill(Color(.windowBackgroundColor).opacity(0.4))
                    .shadow(color: .black.opacity(0.1), radius: 10, y: 5))
            
            VStack(spacing: 8) {
                Text("Audio Input")
                    .font(.system(size: 28, weight: .bold))
                Text("Configure your microphone preferences")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }
    
    private var inputModeSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Input Mode")
                .font(.title2)
                .fontWeight(.semibold)
            
            HStack(spacing: 20) {
                ForEach(AudioInputMode.allCases, id: \.self) { mode in
                    InputModeCard(
                        mode: mode,
                        isSelected: audioDeviceManager.inputMode == mode,
                        action: { audioDeviceManager.selectInputMode(mode) }
                    )
                }
            }
        }
    }
    
    private var customDeviceSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Available Devices")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: { audioDeviceManager.loadAvailableDevices() }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
            
            Text("Note: Selecting a device here will override your Mac\'s system-wide default microphone.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 8)

            VStack(spacing: 12) {
                ForEach(audioDeviceManager.availableDevices, id: \.id) { device in
                    DeviceSelectionCard(
                        name: device.name,
                        isSelected: audioDeviceManager.selectedDeviceID == device.id,
                        isActive: audioDeviceManager.getCurrentDevice() == device.id
                    ) {
                        audioDeviceManager.selectDevice(id: device.id)
                    }
                }
            }
        }
    }
    
    private var prioritizedDevicesSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            if audioDeviceManager.availableDevices.isEmpty {
                emptyDevicesState
            } else {
                prioritizedDevicesContent
                Divider().padding(.vertical, 8)
                availableDevicesContent
            }
        }
    }
    
    private var prioritizedDevicesContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Prioritized Devices")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Devices will be used in order of priority. If a device is unavailable, the next one will be tried. If no prioritized device is available, the system default microphone will be used.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Warning: Using a prioritized device will override your Mac\'s system-wide default microphone if it becomes active.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
            
            if audioDeviceManager.prioritizedDevices.isEmpty {
                Text("No prioritized devices")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                prioritizedDevicesList
            }
        }
    }
    
    private var availableDevicesContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Available Devices")
                .font(.title2)
                .fontWeight(.semibold)
            
            availableDevicesList
        }
    }
    
    private var emptyDevicesState: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.slash.circle.fill")
                .font(.system(size: 48))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            
            VStack(spacing: 8) {
                Text("No Audio Devices")
                    .font(.headline)
                Text("Connect an audio input device to get started")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(CardBackground(isSelected: false))
    }
    
    private var prioritizedDevicesList: some View {
        VStack(spacing: 12) {
            ForEach(audioDeviceManager.prioritizedDevices.sorted(by: { $0.priority < $1.priority })) { device in
                devicePriorityCard(for: device)
            }
        }
    }
    
    private func devicePriorityCard(for prioritizedDevice: PrioritizedDevice) -> some View {
        let device = audioDeviceManager.availableDevices.first(where: { $0.uid == prioritizedDevice.id })
        return DevicePriorityCard(
            name: prioritizedDevice.name,
            priority: prioritizedDevice.priority,
            isActive: device.map { audioDeviceManager.getCurrentDevice() == $0.id } ?? false,
            isPrioritized: true,
            isAvailable: device != nil,
            canMoveUp: prioritizedDevice.priority > 0,
            canMoveDown: prioritizedDevice.priority < audioDeviceManager.prioritizedDevices.count - 1,
            onTogglePriority: { audioDeviceManager.removePrioritizedDevice(id: prioritizedDevice.id) },
            onMoveUp: { moveDeviceUp(prioritizedDevice) },
            onMoveDown: { moveDeviceDown(prioritizedDevice) }
        )
    }
    
    private var availableDevicesList: some View {
        let unprioritizedDevices = audioDeviceManager.availableDevices.filter { device in
            !audioDeviceManager.prioritizedDevices.contains { $0.id == device.uid }
        }
        
        return Group {
            if unprioritizedDevices.isEmpty {
                Text("No additional devices available")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(unprioritizedDevices, id: \.id) { device in
                    DevicePriorityCard(
                        name: device.name,
                        priority: nil,
                        isActive: audioDeviceManager.getCurrentDevice() == device.id,
                        isPrioritized: false,
                        isAvailable: true,
                        canMoveUp: false,
                        canMoveDown: false,
                        onTogglePriority: { audioDeviceManager.addPrioritizedDevice(uid: device.uid, name: device.name) },
                        onMoveUp: {},
                        onMoveDown: {}
                    )
                }
            }
        }
    }
    
    private func moveDeviceUp(_ device: PrioritizedDevice) {
        guard device.priority > 0,
              let currentIndex = audioDeviceManager.prioritizedDevices.firstIndex(where: { $0.id == device.id })
        else { return }
        
        var devices = audioDeviceManager.prioritizedDevices
        devices.swapAt(currentIndex, currentIndex - 1)
        updatePriorities(devices)
    }
    
    private func moveDeviceDown(_ device: PrioritizedDevice) {
        guard device.priority < audioDeviceManager.prioritizedDevices.count - 1,
              let currentIndex = audioDeviceManager.prioritizedDevices.firstIndex(where: { $0.id == device.id })
        else { return }
        
        var devices = audioDeviceManager.prioritizedDevices
        devices.swapAt(currentIndex, currentIndex + 1)
        updatePriorities(devices)
    }
    
    private func updatePriorities(_ devices: [PrioritizedDevice]) {
        let updatedDevices = devices.enumerated().map { index, device in
            PrioritizedDevice(id: device.id, name: device.name, priority: index)
        }
        audioDeviceManager.updatePriorities(devices: updatedDevices)
    }

    // MARK: - Recording Configuration Section

    @State private var selectedChannelMode: AudioChannelMode = {
        if let modeString = UserDefaults.standard.audioChannelMode,
           let mode = AudioChannelMode(rawValue: modeString) {
            return mode
        }
        return .mono
    }()

    @State private var customChannelCount: Int = UserDefaults.standard.audioCustomChannelCount
    @State private var autoDownmix: Bool = UserDefaults.standard.autoDownmixForTranscription

    private var recordingConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Recording Configuration")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 16) {
                // Channel Mode Picker
                VStack(alignment: .leading, spacing: 12) {
                    Text("Channel Configuration")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(AudioChannelMode.allCases, id: \.self) { mode in
                            HStack {
                                Image(systemName: selectedChannelMode == mode ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedChannelMode == mode ? .blue : .secondary)
                                Text(mode.rawValue)
                                    .font(.body)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedChannelMode = mode
                                UserDefaults.standard.audioChannelMode = mode.rawValue
                            }
                        }
                    }
                    .padding(.leading, 4)

                    // Show device capability info
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                        Text("Current device supports up to \(audioDeviceManager.currentDeviceMaxChannels) channel(s)")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                }

                // Custom channel picker (if mode is custom)
                if selectedChannelMode == .custom {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Channel Count:")
                                .font(.subheadline)
                            Stepper("\(customChannelCount)", value: $customChannelCount, in: 1...Int(audioDeviceManager.currentDeviceMaxChannels))
                                .frame(width: 120)
                                .onChange(of: customChannelCount) { newValue in
                                    UserDefaults.standard.audioCustomChannelCount = newValue
                                }
                        }
                    }
                    .padding(.leading, 4)
                }

                Divider().padding(.vertical, 8)

                // Transcription handling
                VStack(alignment: .leading, spacing: 12) {
                    Text("Transcription Compatibility")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Toggle("Automatically downmix to mono for transcription", isOn: $autoDownmix)
                        .toggleStyle(.switch)
                        .onChange(of: autoDownmix) { newValue in
                            UserDefaults.standard.autoDownmixForTranscription = newValue
                        }

                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                        Text("When enabled, multi-channel recordings will be downmixed to mono before transcription. The original multi-channel file is preserved.")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundColor(.secondary)
                }
            }
            .padding(20)
            .background(CardBackground(isSelected: false))
        }
    }
}

struct InputModeCard: View {
    let mode: AudioInputMode
    let isSelected: Bool
    let action: () -> Void
    
    private var icon: String {
        switch mode {
        case .systemDefault: return "macbook.and.iphone"
        case .custom: return "mic.circle.fill"
        case .prioritized: return "list.number"
        }
    }
    
    private var description: String {
        switch mode {
        case .systemDefault: return "Use system's default input device"
        case .custom: return "Select a specific input device"
        case .prioritized: return "Set up device priority order"
        }
    }
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? .blue : .secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.rawValue)
                        .font(.headline)
                    
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(CardBackground(isSelected: isSelected))
        }
        .buttonStyle(.plain)
    }
}

struct DeviceSelectionCard: View {
    let name: String
    let isSelected: Bool
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.system(size: 18))
                
                Text(name)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                if isActive {
                    Label("Active", systemImage: "wave.3.right")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(.green.opacity(0.1))
                        )
                }
            }
            .padding()
            .background(CardBackground(isSelected: isSelected))
        }
        .buttonStyle(.plain)
    }
}

struct DevicePriorityCard: View {
    let name: String
    let priority: Int?
    let isActive: Bool
    let isPrioritized: Bool
    let isAvailable: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onTogglePriority: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    
    var body: some View {
        HStack {
            // Priority number or dash
            if let priority = priority {
                Text("\(priority + 1)")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
            } else {
                Text("-")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
            }
            
            // Device name
            Text(name)
                .foregroundStyle(isAvailable ? .primary : .secondary)
            
            Spacer()
            
            // Status and Controls
            HStack(spacing: 12) {
                // Active status
                if isActive {
                    Label("Active", systemImage: "wave.3.right")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(.green.opacity(0.1))
                        )
                } else if !isAvailable && isPrioritized {
                    Label("Unavailable", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color(.windowBackgroundColor).opacity(0.4))
                        )
                }
                
                // Priority controls (only show if prioritized)
                if isPrioritized {
                    HStack(spacing: 2) {
                        Button(action: onMoveUp) {
                            Image(systemName: "chevron.up")
                                .foregroundStyle(canMoveUp ? .blue : .secondary.opacity(0.5))
                        }
                        .disabled(!canMoveUp)
                        
                        Button(action: onMoveDown) {
                            Image(systemName: "chevron.down")
                                .foregroundStyle(canMoveDown ? .blue : .secondary.opacity(0.5))
                        }
                        .disabled(!canMoveDown)
                    }
                }
                
                // Toggle priority button
                Button(action: onTogglePriority) {
                    Image(systemName: isPrioritized ? "minus.circle.fill" : "plus.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isPrioritized ? .red : .blue)
                }
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(CardBackground(isSelected: false))
    }
} 
