import SwiftUI
import AVFoundation
import AppKit
import KeyboardShortcuts

struct OnboardingPermission: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let icon: String
    let type: PermissionType
    
    enum PermissionType {
        case microphone
        case audioDeviceSelection
        case accessibility
        case screenRecording
        case keyboardShortcut
        
        var systemName: String {
            switch self {
            case .microphone: return "mic"
            case .audioDeviceSelection: return "headphones"
            case .accessibility: return "accessibility"
            case .screenRecording: return "rectangle.inset.filled.and.person.filled"
            case .keyboardShortcut: return "keyboard"
            }
        }
    }
}

struct OnboardingPermissionsView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject private var hotkeyManager: HotkeyManager
    @ObservedObject private var audioDeviceManager = AudioDeviceManager.shared
    @State private var currentPermissionIndex = 0
    @State private var permissionStates: [Bool] = [false, false, false, false, false]
    @State private var showAnimation = false
    @State private var scale: CGFloat = 0.8
    @State private var opacity: CGFloat = 0
    @State private var showModelDownload = false
    
    private let permissions: [OnboardingPermission] = [
        OnboardingPermission(
            title: "Microphone Access",
            description: "Enable your microphone to start speaking and converting your voice to text instantly.",
            icon: "waveform",
            type: .microphone
        ),
        OnboardingPermission(
            title: "Microphone Selection",
            description: "Select the audio input device you want to use with VoiceInk.",
            icon: "headphones",
            type: .audioDeviceSelection
        ),
        OnboardingPermission(
            title: "Accessibility Access",
            description: "Allow VoiceInk to help you type anywhere in your Mac.",
            icon: "accessibility",
            type: .accessibility
        ),
        OnboardingPermission(
            title: "Screen Recording",
            description: "This helps to improve the accuracy of transcription.",
            icon: "rectangle.inset.filled.and.person.filled",
            type: .screenRecording
        ),
        OnboardingPermission(
            title: "Keyboard Shortcut",
            description: "Set up a keyboard shortcut to quickly access VoiceInk from anywhere.",
            icon: "keyboard",
            type: .keyboardShortcut
        )
    ]
    
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                ZStack {
                    // Reusable background
                    OnboardingBackgroundView()
                    
                    VStack(spacing: 40) {
                        // Progress indicator
                        HStack(spacing: 8) {
                            ForEach(0..<permissions.count, id: \.self) { index in
                                Circle()
                                    .fill(index <= currentPermissionIndex ? Color.accentColor : Color.white.opacity(0.1))
                                    .frame(width: 8, height: 8)
                                    .scaleEffect(index == currentPermissionIndex ? 1.2 : 1.0)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPermissionIndex)
                            }
                        }
                        .padding(.top, 40)
                        
                        // Current permission card
                        VStack(spacing: 30) {
                            // Permission icon
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.1))
                                    .frame(width: 100, height: 100)
                                
                                if permissionStates[currentPermissionIndex] {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 50))
                                        .foregroundColor(.accentColor)
                                        .transition(.scale.combined(with: .opacity))
                                } else {
                                    Image(systemName: permissions[currentPermissionIndex].icon)
                                        .font(.system(size: 40))
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .scaleEffect(scale)
                            .opacity(opacity)
                            
                            // Permission text
                            VStack(spacing: 12) {
                                HStack(spacing: 8) {
                                    Text(permissions[currentPermissionIndex].title)
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                    
                                    if permissions[currentPermissionIndex].type == .screenRecording {
                                        InfoTip(
                                            "VoiceInk captures on-screen text to understand the context of your voice input, which significantly improves transcription accuracy. Your privacy is important: this data is processed locally and is not stored.",
                                            learnMoreURL: "https://tryvoiceink.com/docs/contextual-awareness"
                                        )
                                    }
                                }
                                
                                Text(permissions[currentPermissionIndex].description)
                                    .font(.body)
                                    .foregroundColor(.white.opacity(0.7))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                            .scaleEffect(scale)
                            .opacity(opacity)
                            
                            // Audio device selection (only shown for audio device selection step)
                            if permissions[currentPermissionIndex].type == .audioDeviceSelection {
                                VStack(spacing: 20) {
                                    if audioDeviceManager.availableDevices.isEmpty {
                                        VStack(spacing: 12) {
                                            Image(systemName: "mic.slash.circle.fill")
                                                .font(.system(size: 36))
                                                .symbolRenderingMode(.hierarchical)
                                                .foregroundStyle(.secondary)
                                            
                                            Text("No microphones found")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding()
                                    } else {
                                        styledPicker(
                                            label: "Microphone:",
                                            selectedValue: audioDeviceManager.selectedDeviceID ?? 0,
                                            displayValue: audioDeviceManager.availableDevices.first { $0.id == audioDeviceManager.selectedDeviceID }?.name ?? "Select Device",
                                            options: audioDeviceManager.availableDevices.map { $0.id },
                                            optionDisplayName: { deviceId in
                                                audioDeviceManager.availableDevices.first { $0.id == deviceId }?.name ?? "Unknown Device"
                                            },
                                            onSelection: { deviceId in
                                                audioDeviceManager.selectDevice(id: deviceId)
                                                audioDeviceManager.selectInputMode(.custom)
                                                withAnimation {
                                                    permissionStates[currentPermissionIndex] = true
                                                    showAnimation = true
                                                }
                                            }
                                        )
                                        .onAppear {
                                            if !audioDeviceManager.availableDevices.isEmpty {
                                                if let deviceID = audioDeviceManager.findBestAvailableDevice() {
                                                    audioDeviceManager.selectDevice(id: deviceID)
                                                    audioDeviceManager.selectInputMode(.custom)
                                                    withAnimation {
                                                        permissionStates[currentPermissionIndex] = true
                                                        showAnimation = true
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    
                                    Text("For best results, using your Mac's built-in microphone is recommended.")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                }
                                .scaleEffect(scale)
                                .opacity(opacity)
                            }
                            
                            // Keyboard shortcut recorder (only shown for keyboard shortcut step)
                            if permissions[currentPermissionIndex].type == .keyboardShortcut {
                                hotkeyView(
                                    binding: $hotkeyManager.selectedHotkey1,
                                    shortcutName: .toggleMiniRecorder
                                ) { isConfigured in
                                    withAnimation {
                                        permissionStates[currentPermissionIndex] = isConfigured
                                        showAnimation = isConfigured
                                    }
                                }
                                .scaleEffect(scale)
                                .opacity(opacity)
                            }
                        }
                        .frame(maxWidth: 400)
                        .padding(.vertical, 40)
                        
                        // Action buttons
                        VStack(spacing: 16) {
                            Button(action: requestPermission) {
                                Text(getButtonTitle())
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(width: 200, height: 50)
                                    .background(Color.accentColor)
                                    .cornerRadius(25)
                            }
                            .buttonStyle(ScaleButtonStyle())
                            
                            if !permissionStates[currentPermissionIndex] && 
                               permissions[currentPermissionIndex].type != .keyboardShortcut &&
                               permissions[currentPermissionIndex].type != .audioDeviceSelection {
                                SkipButton(text: "Skip for now") {
                                    moveToNext()
                                }
                            }
                        }
                        .opacity(opacity)
                    }
                    .padding()
                }
            }
            
            if showModelDownload {
                OnboardingModelDownloadView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .onAppear {
            checkExistingPermissions()
            animateIn()
            // Ensure audio devices are loaded
            audioDeviceManager.loadAvailableDevices()
        }
    }
    
    private func animateIn() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            scale = 1
            opacity = 1
        }
    }
    
    private func resetAnimation() {
        scale = 0.8
        opacity = 0
        animateIn()
    }
    
    private func checkExistingPermissions() {
        // Check microphone permission
        permissionStates[0] = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        
        // Check if device is selected
        permissionStates[1] = audioDeviceManager.selectedDeviceID != nil
        
        // Check accessibility permission
        permissionStates[2] = AXIsProcessTrusted()
        
        // Check screen recording permission
        permissionStates[3] = CGPreflightScreenCaptureAccess()
        
        // Check keyboard shortcut
        permissionStates[4] = hotkeyManager.isShortcutConfigured
    }
    
    private func requestPermission() {
        if permissionStates[currentPermissionIndex] {
            moveToNext()
            return
        }
        
        switch permissions[currentPermissionIndex].type {
        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    self.permissionStates[self.currentPermissionIndex] = granted
                    if granted {
                        withAnimation {
                            self.showAnimation = true
                        }
                        self.audioDeviceManager.loadAvailableDevices()
                    }
                }
            }
            
        case .audioDeviceSelection:
            audioDeviceManager.loadAvailableDevices()

            if audioDeviceManager.availableDevices.isEmpty {
                audioDeviceManager.selectInputMode(.custom)
                withAnimation {
                    permissionStates[currentPermissionIndex] = true
                    showAnimation = true
                }
                moveToNext()
                return
            }

            if let deviceID = audioDeviceManager.findBestAvailableDevice() {
                audioDeviceManager.selectDevice(id: deviceID)
                audioDeviceManager.selectInputMode(.custom)
                withAnimation {
                    permissionStates[currentPermissionIndex] = true
                    showAnimation = true
                }
            }
            moveToNext()
            
        case .accessibility:
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options)
            
            // Start checking for permission status
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
                if AXIsProcessTrusted() {
                    timer.invalidate()
                    permissionStates[currentPermissionIndex] = true
                    withAnimation {
                        showAnimation = true
                    }
                }
            }
            
        case .screenRecording:
            // First try to request permission programmatically
            CGRequestScreenCaptureAccess()
            
            // Also open system preferences as fallback
            if let prefpaneURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(prefpaneURL)
            }
            
            // Start checking for permission status
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
                if CGPreflightScreenCaptureAccess() {
                    timer.invalidate()
                    permissionStates[currentPermissionIndex] = true
                    withAnimation {
                        showAnimation = true
                    }
                }
            }
            
        case .keyboardShortcut:
            // The keyboard shortcut is handled by the KeyboardShortcuts.Recorder
            break
        }
    }
    
    private func moveToNext() {
        if currentPermissionIndex < permissions.count - 1 {
            withAnimation {
                currentPermissionIndex += 1
                resetAnimation()
            }
        } else {
            withAnimation {
                showModelDownload = true
            }
        }
    }
    
    private func getButtonTitle() -> String {
        switch permissions[currentPermissionIndex].type {
        case .keyboardShortcut:
            return permissionStates[currentPermissionIndex] ? "Continue" : "Set Shortcut"
        case .audioDeviceSelection:
            return "Continue"
        default:
            return permissionStates[currentPermissionIndex] ? "Continue" : "Enable Access"
        }
    }

    @ViewBuilder
    private func styledPicker<T: Hashable>(
        label: String,
        selectedValue: T,
        displayValue: String,
        options: [T],
        optionDisplayName: @escaping (T) -> String,
        onSelection: @escaping (T) -> Void
    ) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Spacer()
                
                Text(label)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                
                Menu {
                    ForEach(options, id: \.self) { option in
                        Button(action: {
                            onSelection(option)
                        }) {
                            HStack {
                                Text(optionDisplayName(option))
                                if selectedValue == option {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(displayValue)
                            .foregroundColor(.white)
                            .font(.system(size: 16, weight: .medium))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                }
                .menuStyle(.borderlessButton)
                
                Spacer()
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }

    @ViewBuilder
    private func hotkeyView(
        binding: Binding<HotkeyManager.HotkeyOption>,
        shortcutName: KeyboardShortcuts.Name,
        onConfigured: @escaping (Bool) -> Void
    ) -> some View {
        VStack(spacing: 16) {
            styledPicker(
                label: "Shortcut:",
                selectedValue: binding.wrappedValue,
                displayValue: binding.wrappedValue.displayName,
                options: HotkeyManager.HotkeyOption.allCases.filter { $0 != .none && $0 != .custom },
                optionDisplayName: { $0.displayName },
                onSelection: { option in
                    binding.wrappedValue = option
                    onConfigured(option.isModifierKey)
                }
            )

            if binding.wrappedValue.isModifierKey {
                let excludedFlag = binding.wrappedValue.modifierFlag
                styledPicker(
                    label: "Combine with:",
                    selectedValue: hotkeyManager.companionModifier1,
                    displayValue: hotkeyManager.companionModifier1.displayName,
                    options: HotkeyManager.CompanionModifier.allCases.filter { $0 == .none || $0.flag != excludedFlag },
                    optionDisplayName: { $0.displayName },
                    onSelection: { mod in
                        hotkeyManager.companionModifier1 = mod
                    }
                )
            }

            if binding.wrappedValue == .custom {
                KeyboardShortcuts.Recorder(for: shortcutName) { newShortcut in
                    onConfigured(newShortcut != nil)
                }
                .controlSize(.large)
            }
        }
        .onChange(of: binding.wrappedValue) { newValue in
            onConfigured(newValue != .none)
        }
    }
}
