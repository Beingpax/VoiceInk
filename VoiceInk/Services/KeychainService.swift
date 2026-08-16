import Foundation
import Security
import os

/// Stores production credentials in the Data Protection Keychain and local-build credentials in a separate, non-syncing login Keychain namespace.
final class KeychainService {
    static let shared = KeychainService()

    enum Accessibility {
        case afterFirstUnlockThisDeviceOnly

        fileprivate var value: CFString {
            switch self {
            case .afterFirstUnlockThisDeviceOnly:
                return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            }
        }
    }

    enum ReadResult<Value> {
        case value(Value)
        case notFound
        case unavailable(OSStatus)
    }

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "KeychainService")
    #if LOCAL_BUILD
        private let service = "com.prakashjoshipax.VoiceInk.Local"
        private let defaults = UserDefaults.standard
        private let legacyLocalPrefix = "LocalKeychain_"
    #else
        private let service = "com.prakashjoshipax.VoiceInk"
    #endif

    private init() {}

    // MARK: - Public API

    /// Saves a string value to Keychain.
    @discardableResult
    func save(
        _ value: String,
        forKey key: String,
        syncable: Bool = true,
        accessibility: Accessibility? = nil
    ) -> Bool {
        guard let data = value.data(using: .utf8) else {
            logger.error("Failed to convert value to data for key: \(key, privacy: .public)")
            return false
        }
        return save(data: data, forKey: key, syncable: syncable, accessibility: accessibility)
    }

    /// Saves data to Keychain.
    @discardableResult
    func save(
        data: Data,
        forKey key: String,
        syncable: Bool = true,
        accessibility: Accessibility? = nil
    ) -> Bool {
        let query = baseQuery(forKey: key, syncable: syncable)
        var attributes: [String: Any] = [kSecValueData as String: data]
        applyAccessibility(accessibility, to: &attributes)
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess {
            logger.info("Successfully updated keychain item for key: \(key, privacy: .public)")
            removeLegacyLocalFallback(forKey: key)
            return true
        }

        guard updateStatus == errSecItemNotFound else {
            logger.error(
                "Failed to update keychain item for key: \(key, privacy: .public), status: \(updateStatus, privacy: .public)"
            )
            return false
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        applyAccessibility(accessibility, to: &addQuery)
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

        if addStatus == errSecSuccess {
            logger.info("Successfully saved keychain item for key: \(key, privacy: .public)")
            removeLegacyLocalFallback(forKey: key)
            return true
        }

        if addStatus == errSecDuplicateItem {
            let retryStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if retryStatus == errSecSuccess {
                logger.info("Successfully updated concurrently created keychain item for key: \(key, privacy: .public)")
                removeLegacyLocalFallback(forKey: key)
                return true
            }

            logger.error(
                "Failed to update concurrently created keychain item for key: \(key, privacy: .public), status: \(retryStatus, privacy: .public)"
            )
            return false
        }

        logger.error(
            "Failed to save keychain item for key: \(key, privacy: .public), status: \(addStatus, privacy: .public)"
        )
        return false
    }

    /// Retrieves a string value from Keychain.
    func getString(forKey key: String, syncable: Bool = true) -> String? {
        guard let data = getData(forKey: key, syncable: syncable) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Retrieves a string while distinguishing missing data from unavailable storage.
    func readString(forKey key: String, syncable: Bool = true) -> ReadResult<String> {
        switch readData(forKey: key, syncable: syncable) {
        case .value(let data):
            guard let value = String(data: data, encoding: .utf8) else {
                logger.error("Failed to decode keychain string for key: \(key, privacy: .public)")
                return .unavailable(errSecDecode)
            }
            return .value(value)
        case .notFound:
            return .notFound
        case .unavailable(let status):
            return .unavailable(status)
        }
    }

    /// Retrieves data from Keychain.
    func getData(forKey key: String, syncable: Bool = true) -> Data? {
        guard case .value(let data) = readData(forKey: key, syncable: syncable) else {
            return nil
        }
        return data
    }

    /// Retrieves data while preserving the Security framework status.
    func readData(forKey key: String, syncable: Bool = true) -> ReadResult<Data> {
        var query = baseQuery(forKey: key, syncable: syncable)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess {
            guard let data = result as? Data else {
                logger.error("Keychain returned invalid data for key: \(key, privacy: .public)")
                return .unavailable(errSecDecode)
            }
            return .value(data)
        }

        if status == errSecItemNotFound {
            #if LOCAL_BUILD
                if let legacyData = defaults.data(forKey: legacyLocalPrefix + key) {
                    _ = save(data: legacyData, forKey: key, syncable: false)
                    return .value(legacyData)
                }
            #endif

            return .notFound
        }

        logger.error(
            "Failed to retrieve keychain item for key: \(key, privacy: .public), status: \(status, privacy: .public)"
        )
        return .unavailable(status)
    }

    /// Deletes an item from Keychain.
    @discardableResult
    func delete(forKey key: String, syncable: Bool = true) -> Bool {
        let query = baseQuery(forKey: key, syncable: syncable)
        let status = SecItemDelete(query as CFDictionary)

        if status == errSecSuccess || status == errSecItemNotFound {
            removeLegacyLocalFallback(forKey: key)
            if status == errSecSuccess {
                logger.info("Successfully deleted keychain item for key: \(key, privacy: .public)")
            }
            return true
        } else {
            logger.error(
                "Failed to delete keychain item for key: \(key, privacy: .public), status: \(status, privacy: .public)"
            )
            return false
        }
    }

    /// Checks if a key exists in Keychain.
    func exists(forKey key: String, syncable: Bool = true) -> Bool {
        var query = baseQuery(forKey: key, syncable: syncable)
        query[kSecReturnData as String] = kCFBooleanFalse

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        #if LOCAL_BUILD
            if status == errSecItemNotFound {
                return defaults.data(forKey: legacyLocalPrefix + key) != nil
            }
        #endif

        return status == errSecSuccess
    }

    // MARK: - Private Helpers

    /// Creates a base Keychain query.
    private func baseQuery(forKey key: String, syncable: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        #if !LOCAL_BUILD
            query[kSecUseDataProtectionKeychain as String] = true

            if syncable {
                query[kSecAttrSynchronizable as String] = kCFBooleanTrue
            }
        #endif

        return query
    }

    private func applyAccessibility(_ accessibility: Accessibility?, to attributes: inout [String: Any]) {
        #if !LOCAL_BUILD
            if let accessibility {
                attributes[kSecAttrAccessible as String] = accessibility.value
            }
        #endif
    }

    // Removes the old local UserDefaults copy after secure storage succeeds or the credential is deleted.
    private func removeLegacyLocalFallback(forKey key: String) {
        #if LOCAL_BUILD
            defaults.removeObject(forKey: legacyLocalPrefix + key)
        #endif
    }
}
