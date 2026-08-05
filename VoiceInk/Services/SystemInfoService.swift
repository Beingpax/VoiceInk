import AVFoundation
import AppKit
import Carbon.HIToolbox
import Foundation

class SystemInfoService {
    static let shared = SystemInfoService()

    private init() {}

    func getSystemInfoString() -> String {
        let info = """
            === VOICEINK SYSTEM INFORMATION ===
            Generated: \(Self.englishTimestamp())

            APP INFORMATION:
            App Version: \(getAppVersion())
            Build Version: \(getBuildVersion())
            License Status: \(getLicenseStatus())

            OPERATING SYSTEM:
            macOS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)

            HARDWARE INFORMATION:
            Device Model: \(getMacModel())
            CPU: \(getCPUInfo())
            Memory: \(getMemoryInfo())
            Architecture: \(getArchitecture())

            AUDIO SETTINGS:
            Input Mode: \(getAudioInputMode())
            Current Audio Device: \(getCurrentAudioDevice())
            Available Audio Devices: \(getAvailableAudioDevices())

            HOTKEY SETTINGS:
            Primary Shortcut: \(getPrimaryShortcut())
            Primary Shortcut Detail: \(detailedShortcutDescription(for: .primaryRecording))
            Primary Selection: \(UserDefaults.standard.string(forKey: "primaryRecordingShortcut") ?? "unset")
            Primary Mode: \(UserDefaults.standard.string(forKey: "primaryRecordingShortcutMode") ?? "unset")
            Secondary Shortcut: \(getSecondaryShortcut())
            Secondary Shortcut Detail: \(detailedShortcutDescription(for: .secondaryRecording))
            Secondary Selection: \(UserDefaults.standard.string(forKey: "secondaryRecordingShortcut") ?? "unset")
            Secondary Mode: \(UserDefaults.standard.string(forKey: "secondaryRecordingShortcutMode") ?? "unset")
            Utility Shortcuts: \(utilityShortcutsDescription())
            Mode Shortcuts: \(modeShortcutsDescription())
            Event Tap Install: \(ShortcutMonitor.allOwnersInstallSummary)
            Event Tap Live Enabled: \(ShortcutMonitor.allOwnersLiveTapSummary)
            Accessibility Trusted: \(AXIsProcessTrusted() ? "true" : "false")
            Listen Event Access (Input Monitoring): \(CGPreflightListenEventAccess() ? "true" : "false")
            Post Event Access: \(CGPreflightPostEventAccess() ? "true" : "false")
            Secure Event Input Enabled: \(IsSecureEventInputEnabled() ? "true" : "false")
            Shortcut Config Issues: \(shortcutConfigIssuesDescription())
            Shortcut Permission Implication: \(ShortcutDiagnostics.permissionSnapshot().humanSummary)
            Middle-Click Recording: \(UserDefaults.standard.bool(forKey: "isMiddleClickToggleEnabled"))
            Middle-Click Activation Delay: \(UserDefaults.standard.integer(forKey: "middleClickActivationDelay")) ms

            TRANSCRIPTION SETTINGS:
            Selected Model: \(getCurrentTranscriptionModel())
            Selected Language: \(getCurrentLanguage())
            AI Enhancement: \(getAIEnhancementStatus())
            AI Provider: \(getAIProvider())
            AI Model: \(getAIModel())

            UI SETTINGS:
            Hide Dock Icon: \(UserDefaults.standard.bool(forKey: "IsMenuBarOnly"))
            Recorder Style: \(UserDefaults.standard.string(forKey: "RecorderType") ?? "mini")

            RECORDING FEEDBACK:
            Sound Feedback: \(CustomSoundManager.shared.hasAnyRecordingSoundEnabled)
            Pause Media While Recording: \(UserDefaults.standard.bool(forKey: "isPauseMediaEnabled"))
            Mute Audio While Recording: \(UserDefaults.standard.bool(forKey: "isSystemMuteEnabled"))
            Audio Resumption Delay: \(UserDefaults.standard.double(forKey: "audioResumptionDelay"))s

            CLIPBOARD & PASTE SETTINGS:
            Restore Clipboard After Paste: \(UserDefaults.standard.bool(forKey: "restoreClipboardAfterPaste"))
            Clipboard Restore Delay: \(UserDefaults.standard.double(forKey: "clipboardRestoreDelay"))s
            Paste Method: \(PasteMethod.current().displayName)

            DATA CLEANUP SETTINGS:
            Auto-Delete Transcriptions: \(UserDefaults.standard.bool(forKey: CleanupSettingsKeys.isTranscriptionCleanupEnabled))
            Transcription Retention: \(UserDefaults.standard.integer(forKey: CleanupSettingsKeys.transcriptionRetentionMinutes)) minutes
            Auto-Delete Audio Files: \(UserDefaults.standard.bool(forKey: CleanupSettingsKeys.isAudioCleanupEnabled))
            Audio Retention Period: \(UserDefaults.standard.integer(forKey: CleanupSettingsKeys.audioRetentionPeriod)) days

            PERMISSIONS:
            Accessibility: \(getAccessibilityStatus())
            Screen Recording: \(getScreenRecordingStatus())
            Microphone: \(getMicrophoneStatus())
            """

        return info
    }

    func copySystemInfoToClipboard() {
        let info = getSystemInfoString()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(info, forType: .string)
    }

    private func getAppVersion() -> String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private func getBuildVersion() -> String {
        return Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    private func getMacModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &machine, &size, nil, 0)
        return String(cString: machine)
    }

    private func getCPUInfo() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    private func getMemoryInfo() -> String {
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let gibibytes = Double(totalMemory) / 1_073_741_824
        return String(format: "%.2f GB (%llu bytes)", locale: Locale(identifier: "en_US_POSIX"), gibibytes, totalMemory)
    }

    private func getArchitecture() -> String {
        return SystemArchitecture.current
    }

    private func getAudioInputMode() -> String {
        if let mode = UserDefaults.standard.audioInputModeRawValue,
            let audioMode = AudioInputMode(rawValue: mode)
        {
            switch audioMode {
            case .systemDefault:
                return "System Default"
            case .custom:
                return "Custom Device"
            case .prioritized:
                return "Prioritized"
            }
        }
        return "System Default"
    }

    private func getCurrentAudioDevice() -> String {
        let audioManager = AudioDeviceManager.shared
        let deviceID = audioManager.getCurrentDevice()
        if deviceID != 0, let deviceName = audioManager.getDeviceName(deviceID: deviceID) {
            return deviceName
        }
        return "Unknown"
    }

    private func getAvailableAudioDevices() -> String {
        let devices = AudioDeviceManager.shared.availableDevices
        if devices.isEmpty {
            return "None detected"
        }
        return devices.map { $0.name }.joined(separator: ", ")
    }

    private func getPrimaryShortcut() -> String {
        shortcutDescription(for: .primaryRecording)
    }

    private func getSecondaryShortcut() -> String {
        shortcutDescription(for: .secondaryRecording)
    }

    private func shortcutDescription(for action: ShortcutAction) -> String {
        ShortcutStore.shortcut(for: action)?.displayString ?? ""
    }

    private func detailedShortcutDescription(for action: ShortcutAction) -> String {
        if ShortcutStore.isShortcutCleared(for: action) {
            return "cleared"
        }

        guard let shortcut = ShortcutStore.rawShortcut(for: action) else {
            return "nil"
        }

        return shortcut.diagnosticDescription
    }

    private func shortcutConfigIssuesDescription() -> String {
        let issues = ShortcutDiagnostics.configurationSnapshot().issues
        return issues.isEmpty ? "none" : issues.joined(separator: "; ")
    }

    private func utilityShortcutsDescription() -> String {
        let lines = ShortcutAction.globalUtilityActions.compactMap { action -> String? in
            guard let shortcut = ShortcutStore.shortcut(for: action) else {
                return nil
            }
            return "\(action.displayName)=\(shortcut.diagnosticDescription)"
        }

        return lines.isEmpty ? "none" : lines.joined(separator: " | ")
    }

    private func modeShortcutsDescription() -> String {
        let lines = ModeManager.shared.configurations.compactMap { config -> String? in
            let action = ShortcutAction.mode(config.id)
            guard let shortcut = ShortcutStore.shortcut(for: action) else {
                return nil
            }
            let enabled = config.isEnabled ? "on" : "off"
            return "\(config.name)[\(enabled)]=\(shortcut.diagnosticDescription)"
        }

        return lines.isEmpty ? "none" : lines.joined(separator: " | ")
    }


    private func getCurrentTranscriptionModel() -> String {
        if let modelName = ModeManager.shared.currentEffectiveConfiguration?.selectedTranscriptionModelName {
            if let model = TranscriptionModelRegistry.models.first(where: { $0.name == modelName }) {
                return model.displayName
            }
            return modelName
        }
        return "No model selected"
    }

    private func getAIEnhancementStatus() -> String {
        ModeManager.shared.currentEffectiveConfiguration?.isAIEnhancementEnabled == true ? "Enabled" : "Disabled"
    }

    private func getAIProvider() -> String {
        ModeManager.shared.currentEffectiveConfiguration?.selectedAIProvider ?? "None selected"
    }

    private func getAIModel() -> String {
        ModeManager.shared.currentEffectiveConfiguration?.selectedAIModel ?? "None selected"
    }
    private func getAccessibilityStatus() -> String {
        return AXIsProcessTrusted() ? "Granted" : "Not Granted"
    }

    private func getScreenRecordingStatus() -> String {
        return CGPreflightScreenCaptureAccess() ? "Granted" : "Not Granted"
    }

    private func getMicrophoneStatus() -> String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return "Granted"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not Determined"
        @unknown default:
            return "Unknown"
        }
    }

    private func getLicenseStatus() -> String {
        let licenseManager = LicenseManager.shared

        // Check for existing license key and activation
        if licenseManager.licenseKey != nil {
            if licenseManager.activationId != nil
                || !UserDefaults.standard.bool(forKey: "VoiceInkLicenseRequiresActivation")
            {
                return "Licensed (Pro)"
            }
        }

        return "Not Licensed"
    }

    private func getCurrentLanguage() -> String {
        return UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "en"
    }

    private static func englishTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

}
