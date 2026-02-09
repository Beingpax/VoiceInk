import Foundation
import os

/// Manages API keys using secure Keychain storage with automatic migration from UserDefaults.
final class APIKeyManager {
    static let shared = APIKeyManager()

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "APIKeyManager")
    private let keychain = KeychainService.shared
    private let userDefaults = UserDefaults.standard

    private let migrationCompletedKey = "APIKeyMigrationToKeychainCompleted_v2"

    /// Provider to Keychain identifier mapping (iOS compatible for iCloud sync).
    private static let providerToKeychainKey: [String: String] = [
        "groq": "groqAPIKey",
        "deepgram": "deepgramAPIKey",
        "cerebras": "cerebrasAPIKey",
        "gemini": "geminiAPIKey",
        "mistral": "mistralAPIKey",
        "elevenlabs": "elevenLabsAPIKey",
        "soniox": "sonioxAPIKey",
        "openai": "openAIAPIKey",
        "anthropic": "anthropicAPIKey",
        "openrouter": "openRouterAPIKey"
    ]

    /// Legacy UserDefaults to Keychain key mapping for migration.
    private static let userDefaultsToKeychainMapping: [String: String] = [
        "GROQAPIKey": "groqAPIKey",
        "DeepgramAPIKey": "deepgramAPIKey",
        "CerebrasAPIKey": "cerebrasAPIKey",
        "GeminiAPIKey": "geminiAPIKey",
        "MistralAPIKey": "mistralAPIKey",
        "ElevenLabsAPIKey": "elevenLabsAPIKey",
        "SonioxAPIKey": "sonioxAPIKey",
        "OpenAIAPIKey": "openAIAPIKey",
        "AnthropicAPIKey": "anthropicAPIKey",
        "OpenRouterAPIKey": "openRouterAPIKey"
    ]

    private init() {
        migrateFromUserDefaultsIfNeeded()
    }

    // MARK: - Standard Provider API Keys

    /// Saves an API key for a provider.
    @discardableResult
    func saveAPIKey(_ key: String, forProvider provider: String) -> Bool {
        let keyIdentifier = keychainIdentifier(forProvider: provider)
        let success = keychain.save(key, forKey: keyIdentifier)
        if success {
            logger.info("Saved API key for provider: \(provider) with key: \(keyIdentifier)")
            // Clean up any remaining UserDefaults entries (both old and new format)
            cleanupUserDefaultsForProvider(provider)
        }
        return success
    }

    /// Retrieves an API key for a provider.
    func getAPIKey(forProvider provider: String) -> String? {
        let keyIdentifier = keychainIdentifier(forProvider: provider)

        // First try Keychain with new identifier
        if let key = keychain.getString(forKey: keyIdentifier), !key.isEmpty {
            return key
        }

        let oldKey = oldUserDefaultsKey(forProvider: provider)
        if let key = userDefaults.string(forKey: oldKey), !key.isEmpty {
            logger.info("Migrating \(oldKey) to Keychain")
            keychain.save(key, forKey: keyIdentifier)
            userDefaults.removeObject(forKey: oldKey)
            return key
        }

        return nil
    }

    /// Deletes an API key for a provider.
    @discardableResult
    func deleteAPIKey(forProvider provider: String) -> Bool {
        let keyIdentifier = keychainIdentifier(forProvider: provider)
        let success = keychain.delete(forKey: keyIdentifier)
        cleanupUserDefaultsForProvider(provider)
        if success {
            logger.info("Deleted API key for provider: \(provider)")
        }
        return success
    }

    /// Checks if an API key exists for a provider.
    func hasAPIKey(forProvider provider: String) -> Bool {
        return getAPIKey(forProvider: provider) != nil
    }

    // MARK: - Custom Model API Keys

    /// Saves an API key for a custom model.
    @discardableResult
    func saveCustomModelAPIKey(_ key: String, forModelId modelId: UUID) -> Bool {
        let keyIdentifier = customModelKeyIdentifier(for: modelId)
        let success = keychain.save(key, forKey: keyIdentifier)
        if success {
            logger.info("Saved API key for custom model: \(modelId.uuidString)")
        }
        return success
    }

    /// Retrieves an API key for a custom model.
    func getCustomModelAPIKey(forModelId modelId: UUID) -> String? {
        let keyIdentifier = customModelKeyIdentifier(for: modelId)
        return keychain.getString(forKey: keyIdentifier)
    }

    /// Deletes an API key for a custom model.
    @discardableResult
    func deleteCustomModelAPIKey(forModelId modelId: UUID) -> Bool {
        let keyIdentifier = customModelKeyIdentifier(for: modelId)
        let success = keychain.delete(forKey: keyIdentifier)
        if success {
            logger.info("Deleted API key for custom model: \(modelId.uuidString)")
        }
        return success
    }

    // MARK: - Migration

    /// Migrates API keys from UserDefaults to Keychain on first run.
    private func migrateFromUserDefaultsIfNeeded() {
        if userDefaults.bool(forKey: migrationCompletedKey) {
            return
        }

        logger.info("Starting API key migration")
        var migratedCount = 0

        for (oldKey, newKey) in Self.userDefaultsToKeychainMapping {
            if let value = userDefaults.string(forKey: oldKey), !value.isEmpty {
                if keychain.save(value, forKey: newKey) {
                    userDefaults.removeObject(forKey: oldKey)
                    migratedCount += 1
                } else {
                    logger.error("Failed to migrate \(oldKey)")
                }
            }
        }

        migrateCustomModelAPIKeys()
        userDefaults.set(true, forKey: migrationCompletedKey)
        logger.info("Migration completed. Migrated \(migratedCount) API keys.")
    }

    /// Migrates custom model API keys from UserDefaults.
    private func migrateCustomModelAPIKeys() {
        guard let data = userDefaults.data(forKey: "customCloudModels") else {
            return
        }

        struct LegacyCustomCloudModel: Codable {
            let id: UUID
            let apiKey: String
        }

        do {
            let legacyModels = try JSONDecoder().decode([LegacyCustomCloudModel].self, from: data)
            for model in legacyModels where !model.apiKey.isEmpty {
                let keyIdentifier = customModelKeyIdentifier(for: model.id)
                keychain.save(model.apiKey, forKey: keyIdentifier)
            }
        } catch {
            logger.error("Failed to decode legacy custom models: \(error.localizedDescription)")
        }
    }

    // MARK: - Key Identifier Helpers

    /// Returns Keychain identifier for a provider (case-insensitive).
    private func keychainIdentifier(forProvider provider: String) -> String {
        let lowercased = provider.lowercased()
        if let mapped = Self.providerToKeychainKey[lowercased] {
            return mapped
        }
        return "\(lowercased)APIKey"
    }

    /// Returns old UserDefaults key for provider (pre-Keychain format).
    private func oldUserDefaultsKey(forProvider provider: String) -> String {
        switch provider.lowercased() {
        case "groq":
            return "GROQAPIKey"
        case "deepgram":
            return "DeepgramAPIKey"
        case "cerebras":
            return "CerebrasAPIKey"
        case "gemini":
            return "GeminiAPIKey"
        case "mistral":
            return "MistralAPIKey"
        case "elevenlabs":
            return "ElevenLabsAPIKey"
        case "soniox":
            return "SonioxAPIKey"
        case "openai":
            return "OpenAIAPIKey"
        case "anthropic":
            return "AnthropicAPIKey"
        case "openrouter":
            return "OpenRouterAPIKey"
        default:
            return "\(provider)APIKey"
        }
    }

    /// Cleans up UserDefaults entries for a provider.
    private func cleanupUserDefaultsForProvider(_ provider: String) {
        userDefaults.removeObject(forKey: oldUserDefaultsKey(forProvider: provider))
    }

    /// Generates Keychain identifier for custom model API key.
    private func customModelKeyIdentifier(for modelId: UUID) -> String {
        "customModel_\(modelId.uuidString)_APIKey"
    }
}
