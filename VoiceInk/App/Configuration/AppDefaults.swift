import Foundation

enum CleanupSettingsKeys {
    static let isTranscriptionCleanupEnabled = "IsTranscriptionCleanupEnabled"
    static let transcriptionRetentionMinutes = "TranscriptionRetentionMinutes"
    static let isAudioCleanupEnabled = "IsAudioCleanupEnabled"
    static let audioRetentionPeriod = "AudioRetentionPeriod"
    static let lastAutomaticAudioCleanupDate = "AudioCleanupLastAutomaticCleanupDate"
}

enum RecorderDisplaySettingsKeys {
    static let showLiveTranscript = "ShowLiveTranscript"
}

enum CloudTranscriptionSettings {
    static let timeoutKey = "CloudTranscriptionTimeout"
    static let defaultTimeout = 30

    static var timeout: TimeInterval {
        let stored = UserDefaults.standard.integer(forKey: timeoutKey)
        return TimeInterval(stored > 0 ? stored : defaultTimeout)
    }
}

enum AutoLearnSettings {
    static let isEnabledKey = "IsAutoLearnDictionaryEnabled"
    static let providerKey = "AutoLearnDictionaryProvider"
    static let modelKey = "AutoLearnDictionaryModel"
    static let hasFailureKey = "AutoLearnDictionaryHasFailure"
    static let failureMessageKey = "AutoLearnDictionaryFailureMessage"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: isEnabledKey)
    }

    static var selectedProvider: AIProvider? {
        guard let value = UserDefaults.standard.string(forKey: providerKey) else { return nil }
        return AIProvider(rawValue: value)
    }

    static var selectedModel: String? {
        let value = UserDefaults.standard.string(forKey: modelKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    static func recordFailure(_ error: Error) {
        let nsError = error as NSError
        var details = [nsError.localizedDescription]
        if let reason = nsError.localizedFailureReason,
            !reason.isEmpty,
            !details.contains(reason)
        {
            details.append(reason)
        }
        if let suggestion = nsError.localizedRecoverySuggestion,
            !suggestion.isEmpty,
            !details.contains(suggestion)
        {
            details.append(suggestion)
        }
        let message = details
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        UserDefaults.standard.set(true, forKey: hasFailureKey)
        UserDefaults.standard.set(
            message.isEmpty ? "The selected provider or model could not review corrections." : message,
            forKey: failureMessageKey
        )
    }

    static func clearFailure() {
        UserDefaults.standard.set(false, forKey: hasFailureKey)
        UserDefaults.standard.removeObject(forKey: failureMessageKey)
    }
}

enum AppDefaults {
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            // Onboarding & General
            "hasCompletedOnboardingV2": false,
            "hasPreparedOnboardingV2": false,
            "enableAnnouncements": true,

            // Clipboard
            "restoreClipboardAfterPaste": true,
            "clipboardRestoreDelay": 2.0,
            "useAppleScriptPaste": false,

            // Audio & Media
            "isSystemMuteEnabled": true,
            "audioResumptionDelay": 0.0,
            "isPauseMediaEnabled": false,
            CustomSoundManager.SoundType.start.builtInSoundKey: CustomSoundManager.SoundType.start.defaultBuiltInSound
                .rawValue,
            CustomSoundManager.SoundType.stop.builtInSoundKey: CustomSoundManager.SoundType.stop.defaultBuiltInSound
                .rawValue,

            // Recording & Transcription
            "IsTextFormattingEnabled": true,
            "IsVADEnabled": true,
            "SelectedLanguage": "en",
            "AppendTrailingSpace": true,
            "RecorderType": "mini",
            RecorderDisplaySettingsKeys.showLiveTranscript: true,
            CloudTranscriptionSettings.timeoutKey: CloudTranscriptionSettings.defaultTimeout,
            AutoLearnSettings.isEnabledKey: true,

            // Cleanup
            CleanupSettingsKeys.isTranscriptionCleanupEnabled: false,
            CleanupSettingsKeys.transcriptionRetentionMinutes: 1440,
            CleanupSettingsKeys.isAudioCleanupEnabled: false,
            CleanupSettingsKeys.audioRetentionPeriod: 7,

            // UI & Behavior
            "IsMenuBarOnly": false,
            AppAppearancePreference.userDefaultsKey: AppAppearancePreference.system.rawValue,
            AppLanguagePreference.userDefaultsKey: AppLanguagePreference.systemValue,
            // Enhancement
            "SkipShortEnhancement": true,
            "ShortEnhancementWordThreshold": 3,
            EnhancementRequestSettings.timeoutKey: EnhancementRequestSettings.defaultTimeoutSeconds,
            EnhancementRequestSettings.retryOnTimeoutKey: EnhancementRequestSettings.defaultRetryOnTimeout,

            // Model
            "PrewarmModelOnWake": true,

        ])

        PasteMethod.migrateLegacyUserDefaultIfNeeded()
    }
}
