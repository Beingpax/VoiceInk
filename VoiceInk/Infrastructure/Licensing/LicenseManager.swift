import Foundation
import Security
import os

struct StoredLicenseState: Equatable {
    let licenseKey: String?
    let activationId: String?
    let trialStartDate: Date?
}

enum LicenseStorageLoadResult: Equatable {
    case loaded(StoredLicenseState)
    case unavailable(OSStatus)
}

enum TrialStartResult: Equatable {
    case started(Date)
    case existing(Date)
    case unavailable
}

protocol LicenseStoring {
    func loadStoredState() -> LicenseStorageLoadResult
    func storeLicense(key: String, activationId: String?) -> Bool
    func startTrialIfNeeded(at date: Date) -> TrialStartResult
    func resetTrial(at date: Date) -> Bool
    func removeStoredLicense() -> Bool
}

/// Persists license data in the device-local Data Protection Keychain.
final class LicenseManager: LicenseStoring {
    static let shared = LicenseManager()

    private let keychain = KeychainService.shared
    private let accessibilityMigration = LicenseKeychainAccessibilityMigration()
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "LicenseManager")

    private let licenseKeyIdentifier = LicenseKeychainKeys.licenseKey
    private let trialStartDateIdentifier = LicenseKeychainKeys.trialStartDate
    private let activationIdIdentifier = LicenseKeychainKeys.activationId
    private let accessibility = KeychainService.Accessibility.afterFirstUnlockThisDeviceOnly

    private init() {}

    func loadStoredState() -> LicenseStorageLoadResult {
        let result = readStoredState()

        if case .loaded(let state) = result,
            !accessibilityMigration.runIfNeeded(for: state)
        {
            logger.error("License Keychain accessibility migration will be retried on the next launch")
        }

        return result
    }

    func storeLicense(key: String, activationId: String?) -> Bool {
        guard case .loaded(let previousState) = readStoredState() else {
            logger.error("Refusing to overwrite license credentials while the Keychain is unavailable")
            return false
        }

        guard keychain.save(
            key,
            forKey: licenseKeyIdentifier,
            syncable: false,
            accessibility: accessibility
        ) else {
            return false
        }

        guard writeCredential(activationId, forKey: activationIdIdentifier) else {
            if !restoreLicense(
                key: previousState.licenseKey,
                activationId: previousState.activationId
            ) {
                logger.error("Failed to restore previous license credentials after a storage failure")
            }
            return false
        }

        return true
    }

    func startTrialIfNeeded(at date: Date) -> TrialStartResult {
        switch readTrialStartDate() {
        case .value(let existingDate):
            return .existing(existingDate)
        case .notFound:
            guard storeTrialStartDate(date) else { return .unavailable }
            return .started(date)
        case .unavailable:
            return .unavailable
        }
    }

    func resetTrial(at date: Date) -> Bool {
        storeTrialStartDate(date)
    }

    @discardableResult
    func removeStoredLicense() -> Bool {
        let removedKey = keychain.delete(forKey: licenseKeyIdentifier, syncable: false)
        let removedActivation = keychain.delete(forKey: activationIdIdentifier, syncable: false)
        return removedKey && removedActivation
    }

    /// Removes all license and trial data for an explicit full reset.
    func removeAll() {
        removeStoredLicense()
        keychain.delete(forKey: trialStartDateIdentifier, syncable: false)
    }

    private func readStoredState() -> LicenseStorageLoadResult {
        let licenseKey: String?
        switch keychain.readString(forKey: licenseKeyIdentifier, syncable: false) {
        case .value(let value):
            licenseKey = value
        case .notFound:
            licenseKey = nil
        case .unavailable(let status):
            return .unavailable(status)
        }

        let activationId: String?
        switch keychain.readString(forKey: activationIdIdentifier, syncable: false) {
        case .value(let value):
            activationId = value
        case .notFound:
            activationId = nil
        case .unavailable(let status):
            return .unavailable(status)
        }

        let trialStartDate: Date?
        switch readTrialStartDate() {
        case .value(let value):
            trialStartDate = value
        case .notFound:
            let startDate = Date()
            guard storeTrialStartDate(startDate) else {
                return .unavailable(errSecIO)
            }
            trialStartDate = startDate
        case .unavailable(let status):
            return .unavailable(status)
        }

        return .loaded(
            StoredLicenseState(
                licenseKey: licenseKey,
                activationId: activationId,
                trialStartDate: trialStartDate
            )
        )
    }

    private func restoreLicense(key: String?, activationId: String?) -> Bool {
        let restoredKey = writeCredential(key, forKey: licenseKeyIdentifier)
        let restoredActivation = writeCredential(activationId, forKey: activationIdIdentifier)
        return restoredKey && restoredActivation
    }

    private func writeCredential(_ value: String?, forKey identifier: String) -> Bool {
        if let value {
            return keychain.save(
                value,
                forKey: identifier,
                syncable: false,
                accessibility: accessibility
            )
        }

        return keychain.delete(forKey: identifier, syncable: false)
    }

    private func readTrialStartDate() -> KeychainService.ReadResult<Date> {
        readDate(forKey: trialStartDateIdentifier)
    }

    private func readDate(forKey identifier: String) -> KeychainService.ReadResult<Date> {
        switch keychain.readData(forKey: identifier, syncable: false) {
        case .value(let data):
            guard let timestamp = String(data: data, encoding: .utf8),
                let timeInterval = Double(timestamp)
            else {
                logger.error("Stored license date is malformed for key: \(identifier, privacy: .public)")
                let resetDate = Date()
                guard storeDate(resetDate, forKey: identifier) else {
                    return .unavailable(errSecIO)
                }
                return .value(resetDate)
            }
            return .value(Date(timeIntervalSince1970: timeInterval))
        case .notFound:
            return .notFound
        case .unavailable(let status):
            return .unavailable(status)
        }
    }

    private func storeTrialStartDate(_ date: Date) -> Bool {
        storeDate(date, forKey: trialStartDateIdentifier)
    }

    private func storeDate(_ date: Date, forKey identifier: String) -> Bool {
        keychain.save(
            String(date.timeIntervalSince1970),
            forKey: identifier,
            syncable: false,
            accessibility: accessibility
        )
    }
}
