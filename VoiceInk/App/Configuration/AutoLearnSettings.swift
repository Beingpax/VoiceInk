import Foundation

enum AutoLearnSettings {
    static let isEnabledKey = "IsAutoLearnDictionaryEnabled"
    static let minimumCorrectionsKey = "AutoLearnDictionaryMinimumCorrections"
    static let defaultMinimumCorrections = 2
    static let reviewerProviderKey = "AutoLearnDictionaryReviewerProvider"
    static let reviewerModelKey = "AutoLearnDictionaryReviewerModel"

    struct ReviewerSelection: Equatable, Sendable {
        let providerName: String
        let modelName: String

        var configurationID: String { "pairs-v3|\(providerName)|\(modelName)" }
        var legacyConfigurationID: String { "legacy-2.21|\(providerName)|\(modelName)" }
    }

    private static let legacyProviderKey = "AutoLearnDictionaryProvider"
    private static let legacyModelKey = "AutoLearnDictionaryModel"
    private static let legacyAIReviewEnabledKey = "AutoLearnDictionaryAIReviewEnabled"

    static var reviewerSelection: ReviewerSelection? {
        let defaults = UserDefaults.standard
        guard let provider = defaults.string(forKey: reviewerProviderKey), !provider.isEmpty else { return nil }
        return ReviewerSelection(providerName: provider, modelName: defaults.string(forKey: reviewerModelKey) ?? "")
    }

    static var usesAIReviewer: Bool { reviewerSelection != nil }
    static var reviewConfigurationID: String? { reviewerSelection?.configurationID }
    static var legacyReviewConfigurationID: String? { reviewerSelection?.legacyConfigurationID }

    static var legacyApprovalConfigurationID: String? {
        let defaults = UserDefaults.standard
        guard let provider = defaults.string(forKey: legacyProviderKey), !provider.isEmpty else { return nil }
        return ReviewerSelection(providerName: provider, modelName: legacyModel(for: provider, defaults: defaults))
            .legacyConfigurationID
    }

    private static let selectionMigratedKey = "AutoLearnDictionaryReviewerSelectionMigratedV1"
    static let hasFailureKey = "AutoLearnDictionaryHasFailure"
    static let failureMessageKey = "AutoLearnDictionaryFailureMessage"
    static let dataHealthFailureKey = "AutoLearnDictionaryIsDataHealthFailure"

    static func registerDefaults(defaults: UserDefaults = .standard) {
        migrateReviewerSelection(defaults: defaults)
        defaults.register(defaults: [isEnabledKey: true, minimumCorrectionsKey: defaultMinimumCorrections])
    }

    // Preserve 2.21 selections unless the user has chosen a new setup.
    private static func migrateReviewerSelection(defaults: UserDefaults) {
        guard !defaults.bool(forKey: selectionMigratedKey) else { return }
        if defaults.object(forKey: reviewerProviderKey) == nil {
            let explicitlyDisabled = defaults.object(forKey: legacyAIReviewEnabledKey) != nil
                && !defaults.bool(forKey: legacyAIReviewEnabledKey)
            let legacyProvider = defaults.string(forKey: legacyProviderKey) ?? ""
            if !explicitlyDisabled, !legacyProvider.isEmpty {
                defaults.set(legacyProvider, forKey: reviewerProviderKey)
                if defaults.object(forKey: reviewerModelKey) == nil {
                    defaults.set(legacyModel(for: legacyProvider, defaults: defaults), forKey: reviewerModelKey)
                }
            }
        }
        // Retain legacy keys for rollback; new installs keep local review.
        defaults.set(true, forKey: selectionMigratedKey)
    }

    private static func legacyModel(for provider: String, defaults: UserDefaults) -> String {
        let choices = [defaults.string(forKey: legacyModelKey),
            defaults.string(forKey: "\(provider)SelectedModel"), AIProvider(rawValue: provider)?.defaultModel]
        return choices.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
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

    static func recordFailure(_ error: Error, defaults: UserDefaults = .standard,
        isDataHealthFailure: Bool = false) {
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
            message.isEmpty ? String(localized: "Auto-Learn is unavailable.") : message,
            forKey: failureMessageKey
        )
        defaults.set(isDataHealthFailure || defaults.bool(forKey: dataHealthFailureKey), forKey: dataHealthFailureKey)
        defaults.set(true, forKey: hasFailureKey)
    }

    static func clearFailure(defaults: UserDefaults = .standard, includingDataHealthFailure: Bool = false) {
        guard includingDataHealthFailure || !defaults.bool(forKey: dataHealthFailureKey) else { return }
        defaults.set(false, forKey: hasFailureKey)
        defaults.removeObject(forKey: failureMessageKey)
        defaults.removeObject(forKey: dataHealthFailureKey)
    }
}
