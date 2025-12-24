import AppIntents
import Foundation
import AppKit

struct ToggleRecorderIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle VoiceInk Recorder"
    static var description = IntentDescription("Start or stop the VoiceInk recorder for voice transcription.")

    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotificationCenter.default.post(name: .toggleRecorder, object: nil)

        let dialog = IntentDialog(stringLiteral: "VoiceInk recorder toggled")
        return .result(dialog: dialog)
    }
}

enum IntentError: Error, LocalizedError {
    case appNotAvailable
    case serviceNotAvailable
    
    var errorDescription: String? {
        switch self {
        case .appNotAvailable:
            return "VoiceInk app is not available"
        case .serviceNotAvailable:
            return "VoiceInk recording service is not available"
        }
    }
}
