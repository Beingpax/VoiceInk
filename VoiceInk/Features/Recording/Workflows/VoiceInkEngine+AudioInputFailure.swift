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

    @MainActor
    static func audioSystemNotRunning() -> AudioInputFailurePresentation {
        AudioInputFailurePresentation(
            title: String(localized: "macOS audio stopped responding. Restart audio, then try recording again."),
            actionLabel: String(localized: "Restart Audio"),
            action: restartCoreAudio
        )
    }

    private static func restartCoreAudio() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \"killall coreaudiod\" with administrator privileges"]
        try? process.run()
    }
}

extension VoiceInkEngine {
    @MainActor
    func recordingAudioFailure(
        for error: Error
    ) -> (title: String, actionLabel: String, action: () -> Void)? {
        guard let recorderError = error as? Recorder.RecorderError else {
            return nil
        }

        let presentation: AudioInputFailurePresentation
        switch recorderError {
        case .noUsableMicrophone(let internalMicrophoneBlockedByClosedLid):
            presentation = .noUsableMicrophone(
                internalMicrophoneBlockedByClosedLid: internalMicrophoneBlockedByClosedLid
            )
        case .audioSystemNotRunning:
            presentation = .audioSystemNotRunning()
        case .couldNotStartRecording:
            return nil
        }
        return (presentation.title, presentation.actionLabel, presentation.action)
    }
}
