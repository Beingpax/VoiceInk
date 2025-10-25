import Foundation
import Security

class KeychainManager {
    // MARK: - Properties
    private let service: String
    private let accessGroup: String?

    // MARK: - Initialization
    init(service: String = Bundle.main.bundleIdentifier ?? "com.prakashjoshipax.VoiceInk",
         accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }
    
    // MARK: - Error Types
    enum KeychainError: LocalizedError {
        case duplicateItem
        case itemNotFound
        case unexpectedData
        case unhandledError(status: OSStatus)
        
        var errorDescription: String? {
            switch self {
            case .duplicateItem:
                return "Item already exists in keychain"
            case .itemNotFound:
                return "Item not found in keychain"
            case .unexpectedData:
                return "Unexpected data format in keychain"
            case .unhandledError(let status):
                return "Keychain error: \(status)"
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Save API key to keychain
    func saveAPIKey(_ key: String, for provider: String) {
        do {
            // Try to update existing item first
            if let _ = getAPIKey(for: provider) {
                try updateAPIKey(key, for: provider)
            } else {
                try addAPIKey(key, for: provider)
            }
        } catch {
            print("Failed to save API key: \(error)")
        }
    }
    
    /// Get API key from keychain
    func getAPIKey(for provider: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                print("Keychain read error: \(status)")
            }
            return nil
        }
        
        guard let existingItem = item as? [String: Any],
              let data = existingItem[kSecValueData as String] as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return key
    }
    
    /// Delete API key from keychain
    func deleteAPIKey(for provider: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }
    
    /// Delete all API keys
    func deleteAllAPIKeys() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }
    
    /// Check if API key exists
    func hasAPIKey(for provider: String) -> Bool {
        return getAPIKey(for: provider) != nil
    }
    
    /// Get all stored providers
    func getAllProviders() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]
        
        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)
        
        guard status == errSecSuccess,
              let existingItems = items as? [[String: Any]] else {
            return []
        }
        
        return existingItems.compactMap { item in
            item[kSecAttrAccount as String] as? String
        }
    }
    
    // MARK: - Private Methods
    
    private func addAPIKey(_ key: String, for provider: String) throws {
        guard let data = key.data(using: .utf8) else {
            throw KeychainError.unexpectedData
        }
        
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        
        // Add access group if specified
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        // Add item
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            if status == errSecDuplicateItem {
                throw KeychainError.duplicateItem
            }
            throw KeychainError.unhandledError(status: status)
        }
    }
    
    private func updateAPIKey(_ key: String, for provider: String) throws {
        guard let data = key.data(using: .utf8) else {
            throw KeychainError.unexpectedData
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider
        ]
        
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unhandledError(status: status)
        }
    }
}

// MARK: - Keychain Manager Extensions
extension KeychainManager {
    /// Migrate API keys from UserDefaults (for upgrades from older versions)
    func migrateFromUserDefaults() {
        let providers = ["ElevenLabs", "OpenAI", "Google"]
        
        for provider in providers {
            let key = "apiKey_\(provider)"
            if let apiKey = UserDefaults.standard.string(forKey: key) {
                saveAPIKey(apiKey, for: provider)
                // Remove from UserDefaults after successful migration
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
    
    /// Validate API key format (basic validation)
    static func isValidAPIKey(_ key: String) -> Bool {
        // Basic validation: not empty and reasonable length
        return !key.isEmpty && key.count >= 20 && key.count <= 200
    }
    
    /// Get formatted provider name for display
    static func formattedProviderName(_ provider: String) -> String {
        switch provider {
        case "ElevenLabs":
            return "ElevenLabs"
        case "OpenAI":
            return "OpenAI"
        case "Google":
            return "Google Cloud"
        default:
            return provider
        }
    }
}

// MARK: - Secure String Extension
extension String {
    /// Create a masked version of the API key for display
    var maskedAPIKey: String {
        guard count > 8 else {
            return String(repeating: "•", count: count)
        }
        
        let prefixCount = 4
        let suffixCount = 4
        let prefix = self.prefix(prefixCount)
        let suffix = self.suffix(suffixCount)
        let maskedMiddle = String(repeating: "•", count: count - prefixCount - suffixCount)
        
        return "\(prefix)\(maskedMiddle)\(suffix)"
    }
    
    /// Check if string looks like an API key
    var looksLikeAPIKey: Bool {
        // Check for common API key patterns
        let patterns = [
            "^sk-[a-zA-Z0-9]{48}$",  // OpenAI pattern
            "^[a-zA-Z0-9]{32,}$",     // Generic alphanumeric
            "^[a-zA-Z0-9-_]{20,}$"    // With dashes and underscores
        ]
        
        for pattern in patterns {
            if self.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        
        return false
    }
}
