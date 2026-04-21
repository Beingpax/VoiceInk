import Foundation
import os

/// Manages API keys using secure Keychain storage.
final class APIKeyManager {
    static let shared = APIKeyManager()

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "APIKeyManager")
    private let keychain = KeychainService.shared

    /// Provider to Keychain identifier mapping (iOS compatible for iCloud sync).
    private static let providerToKeychainKey: [String: String] = [
        "groq": "groqAPIKey",
        "deepgram": "deepgramAPIKey",
        "cerebras": "cerebrasAPIKey",
        "gemini": "geminiAPIKey",
        "mistral": "mistralAPIKey",
        "elevenlabs": "elevenLabsAPIKey",
        "soniox": "sonioxAPIKey",
        "speechmatics": "speechmaticsAPIKey",
        "xai": "xaiAPIKey",
        "openai": "openAIAPIKey",
        "anthropic": "anthropicAPIKey",
        "openrouter": "openRouterAPIKey"
    ]

    private init() {}

    // MARK: - Standard Provider API Keys

    /// Saves an API key for a provider.
    @discardableResult
    func saveAPIKey(_ key: String, forProvider provider: String) -> Bool {
        let keyIdentifier = keychainIdentifier(forProvider: provider)
        let success = keychain.save(key, forKey: keyIdentifier)
        if success {
            logger.info("Saved API key for provider: \(provider, privacy: .public) with key: \(keyIdentifier, privacy: .public)")
        }
        return success
    }

    /// Retrieves an API key for a provider.
    func getAPIKey(forProvider provider: String) -> String? {
        let keyIdentifier = keychainIdentifier(forProvider: provider)
        return keychain.getString(forKey: keyIdentifier)
    }

    /// Deletes an API key for a provider.
    @discardableResult
    func deleteAPIKey(forProvider provider: String) -> Bool {
        let keyIdentifier = keychainIdentifier(forProvider: provider)
        let success = keychain.delete(forKey: keyIdentifier)
        if success {
            logger.info("Deleted API key for provider: \(provider, privacy: .public)")
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
            logger.info("Saved API key for custom model: \(modelId.uuidString, privacy: .public)")
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
            logger.info("Deleted API key for custom model: \(modelId.uuidString, privacy: .public)")
        }
        return success
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

    /// Generates Keychain identifier for custom model API key.
    private func customModelKeyIdentifier(for modelId: UUID) -> String {
        "customModel_\(modelId.uuidString)_APIKey"
    }
}
