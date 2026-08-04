import Foundation
import os

/// Manages license data using secure Keychain storage (non-syncable, device-local).
final class LicenseManager {
    static let shared = LicenseManager()

    private let keychain = KeychainService.shared
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "LicenseManager")

    private let licenseKeyIdentifier = "voiceink.license.key"
    private let trialStartDateIdentifier = "voiceink.license.trialStartDate"
    private let activationIdIdentifier = "voiceink.license.activationId"

    private init() {}

    // MARK: - License Key

    var licenseKey: String? {
        keychain.getString(forKey: licenseKeyIdentifier, syncable: false)
    }

    // MARK: - Trial Start Date

    private(set) var trialStartDate: Date? {
        get {
            guard let data = keychain.getData(forKey: trialStartDateIdentifier, syncable: false),
                let timestamp = String(data: data, encoding: .utf8),
                let timeInterval = Double(timestamp)
            else {
                return nil
            }
            return Date(timeIntervalSince1970: timeInterval)
        }
        set {
            if let date = newValue {
                let timestamp = String(date.timeIntervalSince1970)
                keychain.save(timestamp, forKey: trialStartDateIdentifier, syncable: false)
            } else {
                keychain.delete(forKey: trialStartDateIdentifier, syncable: false)
            }
        }
    }

    @discardableResult
    func startTrialIfNeeded() -> Bool {
        guard trialStartDate == nil else {
            return false
        }

        trialStartDate = Date()
        return true
    }

    // MARK: - Activation ID

    var activationId: String? {
        keychain.getString(forKey: activationIdIdentifier, syncable: false)
    }

    func storeLicense(key: String, activationId: String?) -> Bool {
        let previousKey = licenseKey
        let previousActivationId = self.activationId

        guard keychain.save(key, forKey: licenseKeyIdentifier, syncable: false) else {
            return false
        }

        guard writeCredential(activationId, forKey: activationIdIdentifier) else {
            if !restoreLicense(key: previousKey, activationId: previousActivationId) {
                logger.error("Failed to restore previous license credentials after a storage failure")
            }
            return false
        }

        return true
    }

    private func restoreLicense(key: String?, activationId: String?) -> Bool {
        let restoredKey = writeCredential(key, forKey: licenseKeyIdentifier)
        let restoredActivation = writeCredential(activationId, forKey: activationIdIdentifier)
        return restoredKey && restoredActivation
    }

    private func writeCredential(_ value: String?, forKey identifier: String) -> Bool {
        if let value {
            return keychain.save(value, forKey: identifier, syncable: false)
        }

        return keychain.delete(forKey: identifier, syncable: false)
    }

    @discardableResult
    func removeStoredLicense() -> Bool {
        let removedKey = keychain.delete(forKey: licenseKeyIdentifier, syncable: false)
        let removedActivation = keychain.delete(forKey: activationIdIdentifier, syncable: false)
        return removedKey && removedActivation
    }

    /// Removes all license data (for license removal/reset).
    func removeAll() {
        removeStoredLicense()
        trialStartDate = nil
    }
}
