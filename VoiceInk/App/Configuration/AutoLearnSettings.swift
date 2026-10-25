import Foundation

enum AutoLearnSettings {
    static let isEnabledKey = "IsAutoLearnDictionaryEnabled"
    static let minimumCorrectionsKey = "AutoLearnDictionaryMinimumCorrections"
    static let legacyBacklogDiscardedKey = "AutoLearnDictionaryLegacyBacklogDiscardedV1"
    static let hasFailureKey = "AutoLearnDictionaryHasFailure"
    static let failureMessageKey = "AutoLearnDictionaryFailureMessage"
    static let failureAcknowledgedKey = "AutoLearnDictionaryFailureAcknowledged"

    static func registerDefaults(defaults: UserDefaults = .standard) {
        removeLegacyReviewSettings(defaults: defaults)
        defaults.register(defaults: [isEnabledKey: true, minimumCorrectionsKey: 1])
    }

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

    static func recordFailure(_ error: Error, defaults: UserDefaults = .standard) {
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
        defaults.set(
            message.isEmpty ? String(localized: "The pending corrections could not be reviewed.") : message,
            forKey: failureMessageKey
        )
        defaults.set(false, forKey: failureAcknowledgedKey)
        defaults.set(true, forKey: hasFailureKey)
    }

    static func clearFailure(defaults: UserDefaults = .standard) {
        defaults.set(false, forKey: hasFailureKey)
        defaults.removeObject(forKey: failureMessageKey)
        defaults.removeObject(forKey: failureAcknowledgedKey)
    }

    static func acknowledgeCurrentFailure(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: failureAcknowledgedKey)
    }
}
