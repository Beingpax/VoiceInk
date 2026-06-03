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
    case mode(UUID)
    case recorderPanelEscape
    case recorderPanelMode(Int)

    var userDefaultsKey: String {
        "Shortcut_\(storageName)"
    }

    var isStored: Bool {
        switch self {
        case .recorderPanelEscape, .recorderPanelMode:
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
        case .mode(let id):
            return "mode_\(id.uuidString)"
        case .recorderPanelEscape:
            return "recorderPanelEscape"
        case .recorderPanelMode(let index):
            return "recorderPanelMode_\(index)"
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
            return "Cancel Recording"
        case .openHistoryWindow:
            return "Open History Window"
        case .quickAddToDictionary:
            return "Quick Add to Dictionary"
        case .mode(let id):
            if let config = ModeManager.shared.getConfiguration(with: id) {
                return "\(config.name) Mode"
            }

            if let template = StarterModeCatalog.templates.first(where: { $0.id == id }) {
                return "\(template.name) Mode"
            }

            return "Mode"
        case .recorderPanelEscape:
            return "Recorder Cancel"
        case .recorderPanelMode(let index):
            return "Select Mode \(Self.displayNumber(forRecorderPanelIndex: index))"
        }
    }

    static let globalUtilityActions: [Self] = [
        .pasteLastTranscription,
        .pasteLastEnhancement,
        .retryLastTranscription,
        .openHistoryWindow,
        .quickAddToDictionary
    ]

    static let recorderPanelStoredActions: [Self] = [
        .cancelRecorder
    ]

    static let legacyKeyboardShortcutActions: [Self] = [
        .primaryRecording,
        .secondaryRecording,
        .pasteLastTranscription,
        .pasteLastEnhancement,
        .retryLastTranscription,
        .cancelRecorder,
        .openHistoryWindow,
        .quickAddToDictionary
    ]

    private static func displayNumber(forRecorderPanelIndex index: Int) -> String {
        index == 9 ? "10" : "\(index + 1)"
    }
}
