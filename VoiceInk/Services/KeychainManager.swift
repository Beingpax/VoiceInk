//
//  KeychainManager.swift
//  VoiceInk
//
//  Created by Claude Code
//

import Foundation
import Security

/// A clean and simple manager for securely storing API keys and sensitive data in the Keychain
/// with iCloud sync support for seamless syncing between macOS and iOS devices.
class KeychainManager {

    // MARK: - Singleton

    static let shared = KeychainManager()

    private init() {}

    // MARK: - Configuration

    /// The service identifier for all keychain items
    /// This keeps all VoiceInk keys grouped together in the Keychain
    private let service = "com.prakashjoshipax.VoiceInk"

    /// The access group for sharing keychain items between macOS and iOS apps
    /// Format: TeamID.BundleIdentifier.shared
    private let accessGroup = "V6J6A3VWY2.com.prakashjoshipax.VoiceInk.shared"

    // MARK: - Error Types

    enum KeychainError: Error, LocalizedError {
        case duplicateItem
        case itemNotFound
        case invalidData
        case unexpectedStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .duplicateItem:
                return "Item already exists in Keychain"
            case .itemNotFound:
                return "Item not found in Keychain"
            case .invalidData:
                return "Invalid data format"
            case .unexpectedStatus(let status):
                return "Keychain error: \(status)"
            }
        }
    }

    // MARK: - Public Methods

    /// Save a value to the Keychain with iCloud sync enabled
    /// - Parameters:
    ///   - value: The string value to save (e.g., API key)
    ///   - key: The key to store the value under
    /// - Throws: KeychainError if the operation fails
    func save(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        // First, try to delete any existing item
        try? delete(forKey: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecAttrSynchronizable as String: true,  // Enable iCloud sync
            kSecAttrAccessGroup as String: accessGroup  // Share between macOS and iOS
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Retrieve a value from the Keychain
    /// - Parameter key: The key to retrieve the value for
    /// - Returns: The stored string value, or nil if not found
    func retrieve(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: true,  // Search in synced items
            kSecAttrAccessGroup as String: accessGroup
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    /// Delete a value from the Keychain
    /// - Parameter key: The key to delete
    /// - Throws: KeychainError if the operation fails
    func delete(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: true,
            kSecAttrAccessGroup as String: accessGroup
        ]

        let status = SecItemDelete(query as CFDictionary)

        // It's okay if the item doesn't exist
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Update an existing value in the Keychain
    /// - Parameters:
    ///   - value: The new string value
    ///   - key: The key to update
    /// - Throws: KeychainError if the operation fails
    func update(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: true,
            kSecAttrAccessGroup as String: accessGroup
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        // If item doesn't exist, save it instead
        if status == errSecItemNotFound {
            try save(value, forKey: key)
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Check if a value exists in the Keychain
    /// - Parameter key: The key to check
    /// - Returns: true if the key exists, false otherwise
    func exists(forKey key: String) -> Bool {
        return retrieve(forKey: key) != nil
    }

    /// Delete all VoiceInk keychain items
    /// Use with caution - this will remove all stored API keys
    func deleteAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: true,
            kSecAttrAccessGroup as String: accessGroup
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

// MARK: - Convenience Methods for API Keys

extension KeychainManager {

    /// All API key identifiers used in VoiceInk
    /// Using iOS format (lowercase camelCase) for cross-platform sync compatibility
    enum APIKeyIdentifier: String {
        case openAI = "openAIAPIKey"
        case anthropic = "anthropicAPIKey"
        case gemini = "geminiAPIKey"
        case groq = "groqAPIKey"
        case mistral = "mistralAPIKey"
        case elevenLabs = "elevenLabsAPIKey"
        case deepgram = "deepgramAPIKey"
        case soniox = "sonioxAPIKey"
        case openRouter = "openRouterAPIKey"
        case cerebras = "cerebrasAPIKey"
        case custom = "customAPIKey"
    }

    /// Save an API key for a specific provider
    func saveAPIKey(_ value: String, for identifier: APIKeyIdentifier) throws {
        try save(value, forKey: identifier.rawValue)
    }

    /// Retrieve an API key for a specific provider
    func retrieveAPIKey(for identifier: APIKeyIdentifier) -> String? {
        return retrieve(forKey: identifier.rawValue)
    }

    /// Delete an API key for a specific provider
    func deleteAPIKey(for identifier: APIKeyIdentifier) throws {
        try delete(forKey: identifier.rawValue)
    }

    /// Check if an API key exists for a specific provider
    func hasAPIKey(for identifier: APIKeyIdentifier) -> Bool {
        return exists(forKey: identifier.rawValue)
    }
}

// MARK: - Migration Helper

extension KeychainManager {

    /// Migrate API keys from UserDefaults to Keychain
    /// Maps old UserDefaults keys (uppercase) to new Keychain keys (iOS lowercase format)
    /// This should be called once when transitioning from UserDefaults to Keychain
    /// - Returns: The number of keys successfully migrated
    @discardableResult
    func migrateFromUserDefaults() -> Int {
        let defaults = UserDefaults.standard
        var migratedCount = 0

        // Map old UserDefaults keys to new Keychain identifiers
        let migrationMap: [(oldKey: String, identifier: APIKeyIdentifier)] = [
            ("OpenAIAPIKey", .openAI),
            ("AnthropicAPIKey", .anthropic),
            ("GeminiAPIKey", .gemini),
            ("GROQAPIKey", .groq),
            ("MistralAPIKey", .mistral),
            ("ElevenLabsAPIKey", .elevenLabs),
            ("DeepgramAPIKey", .deepgram),
            ("SonioxAPIKey", .soniox),
            ("OpenRouterAPIKey", .openRouter),
            ("CerebrasAPIKey", .cerebras),
            ("CustomAPIKey", .custom)
        ]

        for (oldKey, identifier) in migrationMap {
            // Check if key exists in UserDefaults (old format)
            if let value = defaults.string(forKey: oldKey),
               !value.isEmpty {
                do {
                    // Save to Keychain with new iOS format key
                    try saveAPIKey(value, for: identifier)

                    // Remove from UserDefaults after successful migration
                    defaults.removeObject(forKey: oldKey)

                    migratedCount += 1
                    print("✓ Migrated \(oldKey) → \(identifier.rawValue)")
                } catch {
                    print("✗ Failed to migrate \(oldKey): \(error.localizedDescription)")
                }
            }
        }

        if migratedCount > 0 {
            defaults.synchronize()
            print("Successfully migrated \(migratedCount) API key(s) to Keychain with iOS format")
        }

        return migratedCount
    }
}
