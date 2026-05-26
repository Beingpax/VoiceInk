import SwiftUI
import AVFoundation
import Cocoa

class PermissionManager: ObservableObject {
    @Published var audioPermissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @Published var isAccessibilityEnabled = false
    @Published var isScreenRecordingEnabled = false
    @Published var isKeyboardShortcutSet = false
    
    init() {
        // Start observing system events that might indicate permission changes
        setupNotificationObservers()
        
        // Initial permission checks
        checkAllPermissions()
    }
    
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupNotificationObservers() {
        // Only observe when app becomes active, as this is a likely time for permissions to have changed
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    @objc private func applicationDidBecomeActive() {
        checkAllPermissions()
    }
    
    func checkAllPermissions() {
        checkAccessibilityPermissions()
        checkScreenRecordingPermission()
        checkAudioPermissionStatus()
        checkKeyboardShortcut()
    }
    
    func checkAccessibilityPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)
        DispatchQueue.main.async {
            self.isAccessibilityEnabled = accessibilityEnabled
        }
    }
    
    func checkScreenRecordingPermission() {
        DispatchQueue.main.async {
            self.isScreenRecordingEnabled = CGPreflightScreenCaptureAccess()
        }
    }
    
    func requestScreenRecordingPermission() {
        CGRequestScreenCaptureAccess()
    }
    
    func checkAudioPermissionStatus() {
        DispatchQueue.main.async {
            self.audioPermissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        }
    }
    
    func requestAudioPermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                self.audioPermissionStatus = granted ? .authorized : .denied
            }
        }
    }
    
    func checkKeyboardShortcut() {
        DispatchQueue.main.async {
            self.isKeyboardShortcutSet = ShortcutStore.shortcut(for: .primaryRecording) != nil
        }
    }
}

struct PermissionCard: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let buttonTitle: String
    let buttonAction: () -> Void
    let checkPermission: () -> Void
    var infoTipMessage: String?
    var infoTipLink: String?
    @State private var isRefreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                // Glowing circular icon container
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isGranted ? Color.green.opacity(0.08) : Color.orange.opacity(0.08))
                        .frame(width: 42, height: 42)

                    Image(systemName: isGranted ? "\(icon).fill" : icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(isGranted ? .green : .orange)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                        
                        if let message = infoTipMessage {
                            if let link = infoTipLink, !link.isEmpty {
                                InfoTip(message, learnMoreURL: link)
                            } else {
                                InfoTip(message)
                            }
                        }
                    }
                    
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.5))
                }
                
                Spacer()
                
                // Status badge with reload on hover/click
                HStack(spacing: 12) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            isRefreshing = true
                        }
                        checkPermission()
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isRefreshing = false
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    }
                    .buttonStyle(.plain)
                    
                    // Status Tag: ✓ Granted or ✗ Not Granted
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isGranted ? Color.green : Color.orange)
                            .frame(width: 5, height: 5)
                        Text(isGranted ? "Granted" : "Not Granted")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(isGranted ? .green : .orange)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isGranted ? Color.green.opacity(0.08) : Color.orange.opacity(0.08))
                    .cornerRadius(6)
                }
            }
            
            if !isGranted {
                Button(action: buttonAction) {
                    HStack {
                        Spacer()
                        Text(buttonTitle)
                        Image(systemName: "arrow.right")
                        Spacer()
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.36, green: 0.28, blue: 0.88))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.01), radius: 4, x: 0, y: 2)
    }
}

struct PermissionsView: View {
    @EnvironmentObject private var recordingShortcutManager: RecordingShortcutManager
    @StateObject private var permissionManager = PermissionManager()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header with Shield Icon
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.1))
                            .frame(width: 56, height: 56)
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(Color(red: 0.36, green: 0.28, blue: 0.88))
                    }
                    .padding(.top, 24)

                    Text("App Permissions")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                    
                    Text("VoiceInk requires the following system permissions to work flawlessly across your Mac")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.5))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 450)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
                .background(Color(red: 0.97, green: 0.97, blue: 0.98))
                
                // Permission Cards List
                VStack(spacing: 12) {
                    // Keyboard Shortcut Permission
                    PermissionCard(
                        icon: "keyboard",
                        title: "Keyboard Shortcut",
                        description: "Configure a global system shortcut to trigger dictation instantly",
                        isGranted: recordingShortcutManager.isShortcutConfigured,
                        buttonTitle: "Configure Shortcut",
                        buttonAction: {
                            NotificationCenter.default.post(
                                name: .navigateToDestination,
                                object: nil,
                                userInfo: ["destination": "Settings"]
                            )
                        },
                        checkPermission: { permissionManager.checkKeyboardShortcut() }
                    )
                    
                    // Audio Permission
                    PermissionCard(
                        icon: "mic",
                        title: "Microphone Access",
                        description: "Allow VoiceInk to capture your high-fidelity voice audio",
                        isGranted: permissionManager.audioPermissionStatus == .authorized,
                        buttonTitle: permissionManager.audioPermissionStatus == .notDetermined ? "Request Permission" : "Open System Settings",
                        buttonAction: {
                            if permissionManager.audioPermissionStatus == .notDetermined {
                                permissionManager.requestAudioPermission()
                            } else {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        },
                        checkPermission: { permissionManager.checkAudioPermissionStatus() }
                    )
                    
                    // Accessibility Permission
                    PermissionCard(
                        icon: "hand.raised",
                        title: "Accessibility Access",
                        description: "Allow VoiceInk to paste transcribed text directly at your active cursor",
                        isGranted: permissionManager.isAccessibilityEnabled,
                        buttonTitle: "Open System Settings",
                        buttonAction: {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        },
                        checkPermission: { permissionManager.checkAccessibilityPermissions() },
                        infoTipMessage: "VoiceInk uses Accessibility permissions to paste the transcribed text directly into other applications at your cursor's position. This allows for a seamless dictation experience across your Mac."
                    )
                    
                    // Screen Recording Permission
                    PermissionCard(
                        icon: "rectangle.on.rectangle",
                        title: "Screen Recording Access",
                        description: "Capture active window context to maximize transcription accuracy",
                        isGranted: permissionManager.isScreenRecordingEnabled,
                        buttonTitle: "Request Permission",
                        buttonAction: {
                            permissionManager.requestScreenRecordingPermission()
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                                NSWorkspace.shared.open(url)
                            }
                        },
                        checkPermission: { permissionManager.checkScreenRecordingPermission() },
                        infoTipMessage: "VoiceInk captures on-screen text to understand the context of your voice input, which significantly improves transcription accuracy. Your privacy is important: this data is processed locally and is not stored.",
                        infoTipLink: "https://tryvoiceink.com/docs/contextual-awareness"
                    )
                }
                .padding(.horizontal, 32)
            }
            .padding(.bottom, 32)
        }
        .background(Color(red: 0.97, green: 0.97, blue: 0.98))
        .onAppear {
            permissionManager.checkAllPermissions()
        }
    }
}

#Preview {
    PermissionsView()
} 
