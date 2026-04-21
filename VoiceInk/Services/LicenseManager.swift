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
        get { keychain.getString(forKey: licenseKeyIdentifier, syncable: false) }
        set {
            if let value = newValue {
                keychain.save(value, forKey: licenseKeyIdentifier, syncable: false)
            } else {
                keychain.delete(forKey: licenseKeyIdentifier, syncable: false)
            }
        }
    }

    // MARK: - Trial Start Date

    var trialStartDate: Date? {
        get {
            guard let data = keychain.getData(forKey: trialStartDateIdentifier, syncable: false),
                  let timestamp = String(data: data, encoding: .utf8),
                  let timeInterval = Double(timestamp) else {
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

    // MARK: - Activation ID

    var activationId: String? {
        get { keychain.getString(forKey: activationIdIdentifier, syncable: false) }
        set {
            if let value = newValue {
                keychain.save(value, forKey: activationIdIdentifier, syncable: false)
            } else {
                keychain.delete(forKey: activationIdIdentifier, syncable: false)
            }
        }
    }

    /// Removes all license data (for license removal/reset).
    func removeAll() {
        licenseKey = nil
        trialStartDate = nil
        activationId = nil
    }
}
