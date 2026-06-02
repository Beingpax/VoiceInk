import Foundation

enum AppDefaults {
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            // Onboarding & General
            "hasCompletedOnboarding": false,
            "enableAnnouncements": true,

            // MCP Server
            "enableMCPServer": true,
            "mcpServerPort": 51089,
            "speakAIQuestionsAloud": false,

            // Clipboard
            "restoreClipboardAfterPaste": true,
            "clipboardRestoreDelay": 2.0,
            "useAppleScriptPaste": false,

            // Audio & Media
            "isSystemMuteEnabled": true,
            "audioResumptionDelay": 0.0,
            "isPauseMediaEnabled": false,
            "isSoundFeedbackEnabled": true,
            CustomSoundManager.SoundType.start.builtInSoundKey: CustomSoundManager.SoundType.start.defaultBuiltInSound.rawValue,
            CustomSoundManager.SoundType.stop.builtInSoundKey: CustomSoundManager.SoundType.stop.defaultBuiltInSound.rawValue,

            // Recording & Transcription
            "IsTextFormattingEnabled": true,
            "SmartSpacingAndCapitalization": true,
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
            "ShowMenuBarIcon": true,
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

            // Supercharged Pro Features (5 Functional, 5 UI/UX)
            "superchargeContextAwareFormatting": true,
            "superchargeSmartFillerStripper": true,
            "superchargeLocalLLMIntegration": true,
            "superchargeSemanticHistorySearch": true,
            "superchargeMultiDestinationRouting": true,
            "superchargeDynamicHUDIsland": true,
            "superchargeDragToTarget": true,
            "superchargeMetalFluidVisualizer": true,
            "superchargeTactileHapticScrubbing": true,
            "superchargeAdaptiveColorExtraction": true,
        ])

        PunctuationCleanupMode.migrateLegacyUserDefaultIfNeeded()
        PasteMethod.migrateLegacyUserDefaultIfNeeded()
    }
}
