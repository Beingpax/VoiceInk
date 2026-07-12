import Foundation

/// Manages license data using secure Keychain storage (non-syncable, device-local).
final class LicenseManager {
    static let shared = LicenseManager()

    private let keychain = KeychainService.shared

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
        let savedKey = keychain.save(key, forKey: licenseKeyIdentifier, syncable: false)
        let savedActivation: Bool

        if let activationId {
            savedActivation = keychain.save(activationId, forKey: activationIdIdentifier, syncable: false)
        } else {
            savedActivation = keychain.delete(forKey: activationIdIdentifier, syncable: false)
        }

        guard savedKey,
            savedActivation,
            licenseKey == key,
            self.activationId == activationId
        else {
            removeStoredLicense()
            return false
        }

        return true
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
