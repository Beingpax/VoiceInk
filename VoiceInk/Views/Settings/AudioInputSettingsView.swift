import SwiftUI

struct AudioInputSettingsView: View {
    @ObservedObject var audioDeviceManager = AudioDeviceManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("IsWhisperModeEnabled") private var isWhisperModeEnabled = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroSection
                mainContent
            }
        }
        .background(Color(red: 0.97, green: 0.97, blue: 0.98))
    }
    
    private var mainContent: some View {
        VStack(spacing: 32) {
            inputModeSection

            switch audioDeviceManager.inputMode {
            case .systemDefault:
                systemDefaultSection
            case .custom:
                customDeviceSection
            case .prioritized:
                prioritizedDevicesSection
            }

            whisperModeSection
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
    }
    
    private var heroSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.1))
                    .frame(width: 56, height: 56)
                Image(systemName: "mic.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Color(red: 0.36, green: 0.28, blue: 0.88))
            }
            .padding(.top, 24)

            Text("Audio Input")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
            
            Text("Configure your preferred microphone options and quiet dictation settings")
                .font(.system(size: 12))
                .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 16)
        .background(Color(red: 0.97, green: 0.97, blue: 0.98))
    }
    
    private var inputModeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Input Mode")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.4))
            
            HStack(spacing: 16) {
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
    
    private var systemDefaultSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Current Device")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.4))

            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.08))
                        .frame(width: 36, height: 32)
                    Image(systemName: "display")
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 0.36, green: 0.28, blue: 0.88))
                }

                Text(audioDeviceManager.getSystemDefaultDeviceName() ?? "No device available")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5, height: 5)
                    Text("Active")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.08))
                .cornerRadius(6)
            }
            .padding(16)
            .background(Color.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.04), lineWidth: 1)
            )
        }
    }

    private var customDeviceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Available Devices")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.4))

                Spacer()

                Button(action: { audioDeviceManager.loadAvailableDevices() }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(red: 0.36, green: 0.28, blue: 0.88))
                }
                .buttonStyle(.borderless)
            }

            VStack(spacing: 10) {
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
        VStack(alignment: .leading, spacing: 16) {
            if audioDeviceManager.availableDevices.isEmpty {
                emptyDevicesState
            } else {
                prioritizedDevicesContent
                availableDevicesContent
            }
        }
    }
    
    private var prioritizedDevicesContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Prioritized Devices")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                Text("Devices will be used in order of priority. If a device is unavailable, the next one will be tried.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.5))
            }
            
            if audioDeviceManager.prioritizedDevices.isEmpty {
                Text("No prioritized devices configured. Add available devices below.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(Color.white)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                    )
            } else {
                PrioritizedDevicesListView(
                    audioDeviceManager: audioDeviceManager,
                    moveDeviceUp: moveDeviceUp,
                    moveDeviceDown: moveDeviceDown
                )
            }
        }
    }
    
    private var availableDevicesContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Available Devices")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.4))
            
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
        .background(Color.white)
        .cornerRadius(12)
    }
    
    private var availableDevicesList: some View {
        let unprioritizedDevices = audioDeviceManager.availableDevices.filter { device in
            !audioDeviceManager.prioritizedDevices.contains { $0.id == device.uid }
        }
        
        return Group {
            if unprioritizedDevices.isEmpty {
                Text("No additional devices available")
                    .font(.system(size: 11))
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

    private var whisperModeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Whisper Mode")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.4))

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(red: 0.54, green: 0.12, blue: 0.92).opacity(0.08))
                            .frame(width: 36, height: 32)
                        Image(systemName: "sparkles")
                            .font(.system(size: 14))
                            .foregroundColor(Color(red: 0.54, green: 0.12, blue: 0.92))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Quiet Dictation Mode")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                        Text("Boosts microphone gain and fine-tunes speech model responsiveness for silent recording.")
                            .font(.system(size: 11))
                            .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.5))
                    }

                    Spacer()
                    
                    Toggle("", isOn: $isWhisperModeEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
            .padding(16)
            .background(isWhisperModeEnabled ? Color(red: 0.54, green: 0.12, blue: 0.92).opacity(0.02) : Color.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isWhisperModeEnabled ? Color(red: 0.54, green: 0.12, blue: 0.92).opacity(0.12) : Color.primary.opacity(0.04), lineWidth: 1.5)
            )
        }
    }
}

struct InputModeCard: View {
    let mode: AudioInputMode
    let isSelected: Bool
    let action: () -> Void

    private var icon: String {
        switch mode {
        case .systemDefault: return "display"
        case .custom: return "mic.circle.fill"
        case .prioritized: return "list.number"
        }
    }

    private var description: String {
        switch mode {
        case .systemDefault: return "Use your Mac's default input device"
        case .custom: return "Select a specific connected microphone"
        case .prioritized: return "Set up customized device backup order"
        }
    }
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSelected ? Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.12) : Color.primary.opacity(0.03))
                            .frame(width: 38, height: 32)
                        Image(systemName: icon)
                            .font(.system(size: 15))
                            .foregroundStyle(isSelected ? Color(red: 0.36, green: 0.28, blue: 0.88) : .secondary)
                    }
                    
                    Spacer()
                    
                    ZStack {
                        Circle()
                            .stroke(isSelected ? Color(red: 0.36, green: 0.28, blue: 0.88) : Color.primary.opacity(0.12), lineWidth: 1.5)
                            .frame(width: 14, height: 14)
                        if isSelected {
                            Circle()
                                .fill(Color(red: 0.36, green: 0.28, blue: 0.88))
                                .frame(width: 8, height: 8)
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.rawValue)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                    
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.15) : Color.primary.opacity(0.04), lineWidth: 1.5)
            )
            .shadow(color: isSelected ? Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.02) : Color.black.opacity(0.01), radius: 6, x: 0, y: 3)
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
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color(red: 0.36, green: 0.28, blue: 0.88) : Color.primary.opacity(0.12), lineWidth: 1.5)
                        .frame(width: 14, height: 14)
                    if isSelected {
                        Circle()
                            .fill(Color(red: 0.36, green: 0.28, blue: 0.88))
                            .frame(width: 8, height: 8)
                    }
                }
                
                Text(name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                
                Spacer()
                
                if isActive {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 5, height: 5)
                        Text("Active")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.08))
                    .cornerRadius(6)
                }
            }
            .padding(14)
            .background(Color.white)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.15) : Color.primary.opacity(0.04), lineWidth: 1)
            )
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
        HStack(spacing: 12) {
            if let priority = priority {
                Text("\(priority + 1)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.36, green: 0.28, blue: 0.88))
                    .frame(width: 18)
            } else {
                Text("-")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 18)
            }
            
            Text(name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isAvailable ? Color(red: 0.12, green: 0.12, blue: 0.18) : .secondary)
            
            Spacer()
            
            HStack(spacing: 10) {
                if isActive {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 5, height: 5)
                        Text("Active")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.08))
                    .cornerRadius(6)
                } else if !isAvailable && isPrioritized {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 5, height: 5)
                        Text("Unavailable")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.08))
                    .cornerRadius(6)
                }
                
                if isPrioritized {
                    HStack(spacing: 4) {
                        Button(action: onMoveUp) {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(canMoveUp ? Color(red: 0.36, green: 0.28, blue: 0.88) : Color.primary.opacity(0.12))
                        }
                        .disabled(!canMoveUp)
                        .buttonStyle(.plain)
                        
                        Button(action: onMoveDown) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(canMoveDown ? Color(red: 0.36, green: 0.28, blue: 0.88) : Color.primary.opacity(0.12))
                        }
                        .disabled(!canMoveDown)
                        .buttonStyle(.plain)
                    }
                }
                
                Button(action: onTogglePriority) {
                    Image(systemName: isPrioritized ? "minus.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(isPrioritized ? .red : Color(red: 0.36, green: 0.28, blue: 0.88))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
        )
    }
}

struct PrioritizedDevicesListView: View {
    @ObservedObject var audioDeviceManager: AudioDeviceManager
    let moveDeviceUp: (PrioritizedDevice) -> Void
    let moveDeviceDown: (PrioritizedDevice) -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            ForEach(audioDeviceManager.prioritizedDevices, id: \.id) { device in
                let activeId = audioDeviceManager.getCurrentDevice()
                let activeUid = audioDeviceManager.availableDevices.first { $0.id == activeId }?.uid
                let isActive = (activeUid ?? "") == device.id
                let isAvailable = audioDeviceManager.availableDevices.contains { $0.uid == device.id }
                let count = audioDeviceManager.prioritizedDevices.count
                DevicePriorityCard(
                    name: device.name,
                    priority: device.priority,
                    isActive: isActive,
                    isPrioritized: true,
                    isAvailable: isAvailable,
                    canMoveUp: device.priority > 0,
                    canMoveDown: device.priority < count - 1,
                    onTogglePriority: {
                        audioDeviceManager.removePrioritizedDevice(id: device.id)
                    },
                    onMoveUp: {
                        moveDeviceUp(device)
                    },
                    onMoveDown: {
                        moveDeviceDown(device)
                    }
                )
            }
        }
    }
}
