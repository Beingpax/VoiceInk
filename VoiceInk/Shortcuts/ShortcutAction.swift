import Foundation

enum ShortcutAction: Hashable {
    case primaryRecording
    case secondaryRecording
    case pasteLastTranscription
    case pasteLastEnhancement
    case retryLastTranscription
    case cancelRecorder
    case openHistoryWindow
    case quickAddToDictionary
    case toggleEnhancement
    case powerMode(UUID)
    case miniRecorderEscape
    case miniRecorderPrompt(Int)
    case miniRecorderPowerMode(Int)

    var userDefaultsKey: String {
        "Shortcut_\(storageName)"
    }

    var isStored: Bool {
        switch self {
        case .miniRecorderEscape, .miniRecorderPrompt, .miniRecorderPowerMode:
            return false
        default:
            return true
        }
    }

    var storageName: String {
        switch self {
        case .primaryRecording:
            return "primaryRecording"
        case .secondaryRecording:
            return "secondaryRecording"
        case .pasteLastTranscription:
            return "pasteLastTranscription"
        case .pasteLastEnhancement:
            return "pasteLastEnhancement"
        case .retryLastTranscription:
            return "retryLastTranscription"
        case .cancelRecorder:
            return "cancelRecorder"
        case .openHistoryWindow:
            return "openHistoryWindow"
        case .quickAddToDictionary:
            return "quickAddToDictionary"
        case .toggleEnhancement:
            return "toggleEnhancement"
        case .powerMode(let id):
            return "powerMode_\(id.uuidString)"
        case .miniRecorderEscape:
            return "miniRecorderEscape"
        case .miniRecorderPrompt(let index):
            return "miniRecorderPrompt_\(index)"
        case .miniRecorderPowerMode(let index):
            return "miniRecorderPowerMode_\(index)"
        }
    }

    var displayName: String {
        switch self {
        case .primaryRecording:
            return "Primary Shortcut"
        case .secondaryRecording:
            return "Secondary Shortcut"
        case .pasteLastTranscription:
            return "Paste Last Transcription"
        case .pasteLastEnhancement:
            return "Paste Last Enhanced Transcription"
        case .retryLastTranscription:
            return "Retry Last Transcription"
        case .cancelRecorder:
            return "Custom Cancel Shortcut"
        case .openHistoryWindow:
            return "Open History Window"
        case .quickAddToDictionary:
            return "Quick Add to Dictionary"
        case .toggleEnhancement:
            return "Toggle Enhancement"
        case .powerMode(let id):
            if let config = PowerModeManager.shared.getConfiguration(with: id) {
                return "\(config.name) Power Mode"
            }

            return "Power Mode"
        case .miniRecorderEscape:
            return "Mini Recorder Cancel"
        case .miniRecorderPrompt(let index):
            return "Select Prompt \(Self.displayNumber(forMiniRecorderIndex: index))"
        case .miniRecorderPowerMode(let index):
            return "Select Power Mode \(Self.displayNumber(forMiniRecorderIndex: index))"
        }
    }

    static let globalUtilityActions: [Self] = [
        .pasteLastTranscription,
        .pasteLastEnhancement,
        .retryLastTranscription,
        .openHistoryWindow,
        .quickAddToDictionary
    ]

    static let miniRecorderStoredActions: [Self] = [
        .cancelRecorder,
        .toggleEnhancement
    ]

    static let legacyKeyboardShortcutActions: [Self] = [
        .primaryRecording,
        .secondaryRecording,
        .pasteLastTranscription,
        .pasteLastEnhancement,
        .retryLastTranscription,
        .cancelRecorder,
        .openHistoryWindow,
        .quickAddToDictionary,
        .toggleEnhancement
    ]

    private static func displayNumber(forMiniRecorderIndex index: Int) -> String {
        index == 9 ? "10" : "\(index + 1)"
    }
}
