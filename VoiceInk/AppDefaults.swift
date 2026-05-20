import Foundation

enum AppDefaults {
    // One-time migration: promote the legacy useAppleScriptPaste bool to the
    // new pasteMethod key so existing users don't silently revert to CGEvent.
    // Must be called after registerDefaults() so the registered default is in
    // place before PasteMethod.current is first read.
    static func migrateIfNeeded() {
        guard UserDefaults.standard.object(forKey: "pasteMethod") == nil else { return }
        if UserDefaults.standard.bool(forKey: "useAppleScriptPaste") {
            UserDefaults.standard.set(PasteMethod.appleScript.rawValue, forKey: "pasteMethod")
        }
        // useAppleScriptPaste == false needs no action: registerDefaults already
        // supplies "cgEvent" as the fallback for a missing pasteMethod key.
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            // Onboarding & General
            "hasCompletedOnboarding": false,
            "enableAnnouncements": true,

            // Clipboard
            "restoreClipboardAfterPaste": true,
            "clipboardRestoreDelay": 2.0,
            "pasteMethod": "cgEvent",

            // Audio & Media
            "isSystemMuteEnabled": true,
            "audioResumptionDelay": 0.0,
            "isPauseMediaEnabled": false,
            "isSoundFeedbackEnabled": true,

            // Recording & Transcription
            "IsTextFormattingEnabled": true,
            "IsVADEnabled": true,
            "RemoveFillerWords": true,
            "RemovePunctuation": false,
            "LowercaseTranscription": false,
            "SelectedLanguage": "en",
            "AppendTrailingSpace": true,
            "showLiveTextPreview": false,
            "RecorderType": "mini",

            // Cleanup
            "IsTranscriptionCleanupEnabled": false,
            "TranscriptionRetentionMinutes": 1440,
            "IsAudioCleanupEnabled": false,
            "AudioRetentionPeriod": 7,

            // UI & Behavior
            "IsMenuBarOnly": false,
            "powerModePersistConfig": false,
            // Shortcuts
            "isMiddleClickToggleEnabled": false,
            "middleClickActivationDelay": 200,

            // Enhancement
            "SkipShortEnhancement": true,
            "ShortEnhancementWordThreshold": 3,
            "EnhancementTimeoutSeconds": 7,
            "EnhancementRetryOnTimeout": true,

            // Model
            "PrewarmModelOnWake": true,

        ])

        PunctuationCleanupMode.migrateLegacyUserDefaultIfNeeded()
    }
}
