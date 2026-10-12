import Foundation

struct AudioInputFailurePresentation {
    let title: String
    let actionLabel: String
    let action: () -> Void

    @MainActor
    static func noUsableMicrophone(
        internalMicrophoneBlockedByClosedLid: Bool
    ) -> AudioInputFailurePresentation {
        let title = internalMicrophoneBlockedByClosedLid
            ? String(
                localized:
                    "No usable microphone is available. Open the lid or connect an external microphone."
            )
            : String(localized: "No usable microphone is available. Choose a microphone in Audio Settings.")

        return AudioInputFailurePresentation(
            title: title,
            actionLabel: String(localized: "Audio Settings"),
            action: AudioSetupNavigator.openAudioSettings
        )
    }
}

extension VoiceInkEngine {
    @MainActor
    func recordingAudioFailure(
        for error: Error
    ) -> (title: String, actionLabel: String, action: () -> Void)? {
        guard let recorderError = error as? Recorder.RecorderError,
            case .noUsableMicrophone(let internalMicrophoneBlockedByClosedLid) = recorderError
        else {
            return nil
        }

        let presentation = AudioInputFailurePresentation.noUsableMicrophone(
            internalMicrophoneBlockedByClosedLid: internalMicrophoneBlockedByClosedLid
        )
        return (presentation.title, presentation.actionLabel, presentation.action)
    }
}
