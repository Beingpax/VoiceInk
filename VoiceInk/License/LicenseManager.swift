import Foundation
import os

/// Manages license data using secure Keychain storage (non-syncable, device-local).
final class LicenseManager {
    static let shared = LicenseManager()

    private let keychain = KeychainService.shared
    private let userDefaults = UserDefaults.standard
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "LicenseManager")

    private let licenseKeyIdentifier = "voiceink.license.key"
    private let trialStartDateIdentifier = "voiceink.license.trialStartDate"
    private let activationIdIdentifier = "voiceink.license.activationId"
    private let migrationCompletedKey = "LicenseKeychainMigrationCompleted"

    private init() {
        migrateFromUserDefaultsIfNeeded()
    }

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

    // MARK: - Migration

    private func migrateFromUserDefaultsIfNeeded() {
        guard !userDefaults.bool(forKey: migrationCompletedKey) else { return }

        // Migrate license key
        if let oldLicenseKey = userDefaults.string(forKey: "VoiceInkLicense"), !oldLicenseKey.isEmpty {
            licenseKey = oldLicenseKey
            userDefaults.removeObject(forKey: "VoiceInkLicense")
            logger.info("Migrated license key to Keychain")
        }

        // Migrate trial start date (from obfuscated storage)
        if let oldTrialDate = getObfuscatedTrialStartDate() {
            trialStartDate = oldTrialDate
            clearObfuscatedTrialStartDate()
            logger.info("Migrated trial start date to Keychain")
        }

        // Migrate activation ID
        if let oldActivationId = userDefaults.string(forKey: "VoiceInkActivationId"), !oldActivationId.isEmpty {
            activationId = oldActivationId
            userDefaults.removeObject(forKey: "VoiceInkActivationId")
            logger.info("Migrated activation ID to Keychain")
        }

        userDefaults.set(true, forKey: migrationCompletedKey)
        logger.info("License migration completed")
    }

    /// Reads the old obfuscated trial start date from UserDefaults.
    private func getObfuscatedTrialStartDate() -> Date? {
        let salt = Obfuscator.getDeviceIdentifier()
        let obfuscatedKey = Obfuscator.encode("VoiceInkTrialStartDate", salt: salt)

        guard let obfuscatedValue = userDefaults.string(forKey: obfuscatedKey),
              let decodedValue = Obfuscator.decode(obfuscatedValue, salt: salt),
              let timestamp = Double(decodedValue) else {
            return nil
        }

        return Date(timeIntervalSince1970: timestamp)
    }

    /// Clears the old obfuscated trial start date from UserDefaults.
    private func clearObfuscatedTrialStartDate() {
        let salt = Obfuscator.getDeviceIdentifier()
        let obfuscatedKey = Obfuscator.encode("VoiceInkTrialStartDate", salt: salt)
        userDefaults.removeObject(forKey: obfuscatedKey)
    }

    /// Removes all license data (for license removal/reset).
    func removeAll() {
        licenseKey = nil
        trialStartDate = nil
        activationId = nil
    }
}
