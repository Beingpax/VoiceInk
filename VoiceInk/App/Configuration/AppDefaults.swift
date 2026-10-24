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
    static let minimumCorrectionsKey = "AutoLearnDictionaryMinimumCorrections"
    static let legacyBacklogDiscardedKey = "AutoLearnDictionaryLegacyBacklogDiscardedV1"
    static let hasFailureKey = "AutoLearnDictionaryHasFailure"
    static let failureMessageKey = "AutoLearnDictionaryFailureMessage"
    static let failureAcknowledgedKey = "AutoLearnDictionaryFailureAcknowledged"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: isEnabledKey)
    }

    static var minimumCorrections: Int {
        clampedMinimumCorrections(UserDefaults.standard.integer(forKey: minimumCorrectionsKey))
    }

    static func clampedMinimumCorrections(_ value: Int) -> Int {
        min(3, max(1, value))
    }

    static func removeLegacyReviewSettings(defaults: UserDefaults = .standard) {
        if defaults.bool(forKey: "AutoLearnDictionaryIsAIReviewFailure") {
            defaults.set(false, forKey: hasFailureKey)
            defaults.removeObject(forKey: failureMessageKey)
            defaults.removeObject(forKey: failureAcknowledgedKey)
        }
        for key in ["AutoLearnDictionaryReviewSchedule", "AutoLearnDictionaryAIReviewEnabled",
            "AutoLearnDictionaryProvider", "AutoLearnDictionaryModel", "AutoLearnDictionaryIsAIReviewFailure"] {
            defaults.removeObject(forKey: key)
        }
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
        UserDefaults.standard.set(
            message.isEmpty ? String(localized: "The pending corrections could not be reviewed.") : message,
            forKey: failureMessageKey
        )
        UserDefaults.standard.set(false, forKey: failureAcknowledgedKey)
        UserDefaults.standard.set(true, forKey: hasFailureKey)
    }

    static func clearFailure() {
        UserDefaults.standard.set(false, forKey: hasFailureKey)
        UserDefaults.standard.removeObject(forKey: failureMessageKey)
        UserDefaults.standard.removeObject(forKey: failureAcknowledgedKey)
    }

    static func acknowledgeCurrentFailure(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: failureAcknowledgedKey)
    }
}

enum OnboardingSettings {
    static let completedV2Key = "hasCompletedOnboardingV2"
    static let preparedV2Key = "hasPreparedOnboardingV2"
}

enum AppDefaults {
    static func registerDefaults() {
        AutoLearnSettings.removeLegacyReviewSettings()
        UserDefaults.standard.register(defaults: [
            // Onboarding & General
            OnboardingSettings.completedV2Key: false,
            OnboardingSettings.preparedV2Key: false,
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
            AutoLearnSettings.minimumCorrectionsKey: 1,

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
            "SkipShortEnhancement": false,
            "ShortEnhancementWordThreshold": 3,
            EnhancementRequestSettings.timeoutKey: EnhancementRequestSettings.defaultTimeoutSeconds,
            EnhancementRequestSettings.retryOnTimeoutKey: EnhancementRequestSettings.defaultRetryOnTimeout,

            // Model
            "PrewarmModelOnWake": true,

        ])

        PasteMethod.migrateLegacyUserDefaultIfNeeded()
    }
}
