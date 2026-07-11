import SwiftUI

enum OnboardingStage: String, CaseIterable {
    case permissions
    case microphone
    case model
    case api
    case experience
    case contextAwareness
    case trust
    case license

    var stepNumber: Int {
        switch self {
        case .permissions:
            return 1
        case .microphone:
            return 2
        case .model:
            return 3
        case .api:
            return 4
        case .experience:
            return 5
        case .contextAwareness:
            return 6
        case .trust:
            return 7
        case .license:
            return 8
        }
    }

    var systemImage: String {
        switch self {
        case .permissions:
            return "lock.shield"
        case .microphone:
            return "mic"
        case .model:
            return "captions.bubble"
        case .api:
            return "checkmark.seal"
        case .experience:
            return "square.grid.2x2.fill"
        case .contextAwareness:
            return "slider.horizontal.3"
        case .trust:
            return "lock.shield"
        case .license:
            return "checkmark.seal.fill"
        }
    }

    var title: String {
        switch self {
        case .permissions:
            return String(localized: "Allow Permissions")
        case .microphone:
            return String(localized: "Choose Microphone")
        case .model:
            return String(localized: "Configure Transcription Model")
        case .api:
            return String(localized: "Verify API Key")
        case .experience:
            return String(localized: "Experience VoiceInk")
        case .contextAwareness:
            return String(localized: "VoiceInk is Context-Aware")
        case .trust:
            return String(localized: "VoiceInk is Open Source")
        case .license:
            return String(localized: "Buy VoiceInk License")
        }
    }

    var subtitle: String {
        switch self {
        case .permissions:
            return String(localized: "Allow VoiceInk to work across all your apps.")
        case .microphone:
            return String(localized: "Pick the microphone VoiceInk should use for recordings.")
        case .model:
            return String(localized: "Use NVIDIA's Parakeet model locally, or connect a cloud transcription provider.")
        case .api:
            return String(
                localized:
                    "VoiceInk uses LLMs to enhance transcripts and perform AI actions. Set up an API key before continuing."
            )
        case .experience:
            return String(localized: "Try a few short samples and see how VoiceInk works before you start.")
        case .contextAwareness:
            return String(
                localized: "VoiceInk can select the right mode from the app you are using and the rules you configure.")
        case .trust:
            return String(localized: "VoiceInk is private by default. No data leaves your device unless you opt in.")
        case .license:
            return String(localized: "Activate an existing key, purchase a license, or start a 7-day free trial.")
        }
    }

    static var baseStepCount: Int {
        4
    }
}

enum OnboardingPermissionKind: String, CaseIterable, Identifiable {
    case microphone
    case accessibility
    case screenRecording

    var id: String { rawValue }

    static var required: [OnboardingPermissionKind] {
        [.microphone, .accessibility]
    }

    var isRequired: Bool {
        Self.required.contains(self)
    }

    var descriptor: OnboardingPermissionDescriptor {
        switch self {
        case .microphone:
            return OnboardingPermissionDescriptor(
                title: "Microphone",
                subtitle: String(localized: "VoiceInk uses your microphone to capture your voice.")
            )

        case .accessibility:
            return OnboardingPermissionDescriptor(
                title: String(localized: "Accessibility"),
                subtitle: String(localized: "VoiceInk uses Accessibility to type transcriptions directly into any app.")
            )

        case .screenRecording:
            return OnboardingPermissionDescriptor(
                title: String(localized: "Screen Recording"),
                subtitle: String(
                    localized: "VoiceInk reads visible screen content to improve the accuracy of transcripts.")
            )
        }
    }
}

struct OnboardingPermissionDescriptor {
    let title: String
    let subtitle: String
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
            return String(localized: "Granted")
        case .needsAccess:
            return String(localized: "Needs access")
        case .denied:
            return String(localized: "Denied")
        case .restricted:
            return String(localized: "Restricted")
        case .unknown:
            return String(localized: "Unknown")
        }
    }

    var color: Color {
        switch self {
        case .granted:
            return AppTheme.Text.secondary
        case .needsAccess:
            return AppTheme.Text.secondary
        case .denied, .restricted:
            return AppTheme.Status.error
        case .unknown:
            return AppTheme.Text.secondary
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
