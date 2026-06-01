import SwiftUI

enum OnboardingStage: String, CaseIterable {
    case permissions
    case model
    case api
    case experience

    var stepNumber: Int {
        switch self {
        case .permissions:
            return 1
        case .model:
            return 2
        case .api:
            return 3
        case .experience:
            return 4
        }
    }

    var systemImage: String {
        switch self {
        case .permissions:
            return "lock.shield"
        case .model:
            return "arrow.down"
        case .api:
            return "key"
        case .experience:
            return "square.grid.2x2.fill"
        }
    }

    var title: String {
        switch self {
        case .permissions:
            return "Allow Permissions"
        case .model:
            return "Download Transcription Model"
        case .api:
            return "Verify API Access"
        case .experience:
            return "Experience VoiceInk"
        }
    }

    var subtitle: String {
        switch self {
        case .permissions:
            return "VoiceInk needs a few macOS permissions before it can record, paste, and use screen context."
        case .model:
            return "VoiceInk will download NVIDIA's Parakeet model to set up fast local transcription."
        case .api:
            return "Connect Groq for enhancement and assistant responses. You can change providers later in Settings."
        case .experience:
            return "Try a few short samples and see how VoiceInk works before you start."
        }
    }

    static var baseStepCount: Int {
        3
    }
}

enum OnboardingPermissionKind: String, CaseIterable, Identifiable {
    case microphone
    case accessibility
    case screenRecording

    var id: String { rawValue }

    static var required: [OnboardingPermissionKind] {
        [.microphone, .accessibility, .screenRecording]
    }

    var isRequired: Bool {
        Self.required.contains(self)
    }

    var descriptor: OnboardingPermissionDescriptor {
        switch self {
        case .microphone:
            return OnboardingPermissionDescriptor(
                title: "Microphone",
                subtitle: "Records your voice for transcription.",
                detail: "VoiceInk cannot start a recording session without this.",
                requirement: "Required"
            )

        case .accessibility:
            return OnboardingPermissionDescriptor(
                title: "Accessibility",
                subtitle: "Lets VoiceInk paste text, auto-send, and read selected text.",
                detail: "This is what allows VoiceInk to work smoothly across apps.",
                requirement: "Required"
            )

        case .screenRecording:
            return OnboardingPermissionDescriptor(
                title: "Screen Recording",
                subtitle: "Lets VoiceInk read visible context for better AI responses.",
                detail: "After granting access, macOS may require you to restart VoiceInk.",
                requirement: "Required"
            )
        }
    }
}

struct OnboardingPermissionDescriptor {
    let title: String
    let subtitle: String
    let detail: String
    let requirement: String
}

enum OnboardingPermissionStatus: Equatable {
    case granted
    case needsAccess
    case denied
    case restricted
    case unknown

    var isGranted: Bool {
        self == .granted
    }

    var requiresSettings: Bool {
        self == .denied || self == .restricted
    }

    var label: String {
        switch self {
        case .granted:
            return "Granted"
        case .needsAccess:
            return "Needs access"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .unknown:
            return "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .granted:
            return Color.primary.opacity(0.72)
        case .needsAccess:
            return Color.primary.opacity(0.72)
        case .denied, .restricted:
            return AppTheme.Status.error
        case .unknown:
            return Color.primary.opacity(0.72)
        }
    }
}

enum PrivacySettingsPane {
    case microphone
    case accessibility
    case screenRecording

    var urlString: String {
        switch self {
        case .microphone:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .accessibility:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .screenRecording:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        }
    }
}
