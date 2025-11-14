import Foundation
import os

/// Service to migrate API keys from UserDefaults to Keychain
class APIKeyMigrationService {
    private static let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "APIKeyMigration")
    private static let migrationKey = "hasCompletedAPIKeyMigrationV1"
    
    /// Run migration on app launch (idempotent, retries until all keys migrated)
    static func migrateAPIKeysIfNeeded() {
        let defaults = UserDefaults.standard
        let keychain = KeychainManager()
        
        // Define all API keys to migrate
        let keysToMigrate: [(userDefaultsKey: String, keychainProvider: String)] = [
            // Cloud Transcription Services (shared with AI Enhancement)
            ("GROQAPIKey", "GROQ"),
            ("ElevenLabsAPIKey", "ElevenLabs"),
            ("DeepgramAPIKey", "Deepgram"),
            ("MistralAPIKey", "Mistral"),
            ("GeminiAPIKey", "Gemini"),
            ("SonioxAPIKey", "Soniox"),
            
            // AI Enhancement Services (some overlap with transcription)
            ("CerebrasAPIKey", "Cerebras"),
            ("AnthropicAPIKey", "Anthropic"),
            ("OpenAIAPIKey", "OpenAI"),
            ("OpenRouterAPIKey", "OpenRouter"),
        ]
        
        var migratedThisRun = 0
        var needsMigration = false
        
        for (oldKey, provider) in keysToMigrate {
            // Check if already migrated (key in Keychain, not in UserDefaults)
            if keychain.hasAPIKey(for: provider) {
                // Already in Keychain, clean up UserDefaults if needed
                if defaults.string(forKey: oldKey) != nil {
                    defaults.removeObject(forKey: oldKey)
                    logger.info("🧹 Cleaned up migrated key from UserDefaults: \(provider, privacy: .public)")
                }
                continue
            }
            
            // Check if key exists in UserDefaults
            if let apiKey = defaults.string(forKey: oldKey), !apiKey.isEmpty {
                needsMigration = true
                
                // Attempt to migrate to Keychain
                keychain.saveAPIKey(apiKey, for: provider)
                
                // Verify save was successful
                if keychain.hasAPIKey(for: provider) {
                    // Successfully migrated, remove from UserDefaults
                    defaults.removeObject(forKey: oldKey)
                    migratedThisRun += 1
                    logger.info("✅ Migrated \(provider, privacy: .public) API key to Keychain")
                } else {
                    // Failed to save to Keychain, keep in UserDefaults for retry
                    logger.error("❌ Failed to migrate \(provider, privacy: .public) - will retry next launch")
                }
            }
        }
        
        if needsMigration {
            logger.notice("🔐 API Key Migration: \(migratedThisRun) keys migrated this run")
        } else if migratedThisRun > 0 {
            logger.notice("🧹 API Key Cleanup: \(migratedThisRun) keys cleaned from UserDefaults")
        } else {
            logger.debug("Migration check complete - all keys already in Keychain")
        }
        
        defaults.synchronize()
    }
    
    /// Force clean all keys from UserDefaults (for testing purposes only)
    static func resetMigration() {
        #if DEBUG
        let defaults = UserDefaults.standard
        let keysToRemove = ["GROQAPIKey", "ElevenLabsAPIKey", "DeepgramAPIKey", 
                            "MistralAPIKey", "GeminiAPIKey", "SonioxAPIKey",
                            "CerebrasAPIKey", "AnthropicAPIKey", "OpenAIAPIKey", "OpenRouterAPIKey"]
        for key in keysToRemove {
            defaults.removeObject(forKey: key)
        }
        defaults.synchronize()
        logger.debug("Migration reset - all keys removed from UserDefaults")
        #endif
    }
}
