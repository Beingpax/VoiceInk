import Foundation

enum LicenseKeychainKeys {
    static let licenseKey = "voiceink.license.key"
    static let trialStartDate = "voiceink.license.trialStartDate"
    static let activationId = "voiceink.license.activationId"
}

struct LicenseKeychainAccessibilityMigration {
    private let keychain: KeychainService
    private let defaults: UserDefaults
    private let migrationKey = "VoiceInkLicenseAccessibilityMigrationV1"
    private let accessibility = KeychainService.Accessibility.afterFirstUnlockThisDeviceOnly

    init(
        keychain: KeychainService = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.keychain = keychain
        self.defaults = defaults
    }

    func runIfNeeded(for state: StoredLicenseState) -> Bool {
        guard !defaults.bool(forKey: migrationKey) else { return true }

        var succeeded = true

        if let licenseKey = state.licenseKey {
            succeeded = keychain.save(
                licenseKey,
                forKey: LicenseKeychainKeys.licenseKey,
                syncable: false,
                accessibility: accessibility
            ) && succeeded
        }

        if let activationId = state.activationId {
            succeeded = keychain.save(
                activationId,
                forKey: LicenseKeychainKeys.activationId,
                syncable: false,
                accessibility: accessibility
            ) && succeeded
        }

        if let trialStartDate = state.trialStartDate {
            succeeded = keychain.save(
                String(trialStartDate.timeIntervalSince1970),
                forKey: LicenseKeychainKeys.trialStartDate,
                syncable: false,
                accessibility: accessibility
            ) && succeeded
        }

        guard succeeded else { return false }

        defaults.set(true, forKey: migrationKey)
        return true
    }
}
