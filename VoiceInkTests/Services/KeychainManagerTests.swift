import XCTest
import Security
@testable import VoiceInk

/// Tests for KeychainManager - critical for API key security
/// FOCUS: OSStatus error handling, thread safety, data validation
@available(macOS 14.0, *)
final class KeychainManagerTests: XCTestCase {
    
    var keychainManager: KeychainManager!
    let testProvider = "TestProvider"
    let testAPIKey = "test-api-key-12345678901234567890"
    
    override func setUp() throws {
        try super.setUp()
        // Use unique service name for testing to avoid conflicts
        keychainManager = KeychainManager(service: "com.test.VoiceInk.KeychainTests")
        
        // Clean up any existing test keys
        try? keychainManager.deleteAllAPIKeys()
    }
    
    override func tearDown() throws {
        // Clean up test keys
        try? keychainManager.deleteAllAPIKeys()
        keychainManager = nil
        try super.tearDown()
    }
    
    // MARK: - Save/Retrieve Tests
    
    func testSaveAndRetrieveAPIKey() {
        // Save API key
        keychainManager.saveAPIKey(testAPIKey, for: testProvider)
        
        // Retrieve API key
        let retrieved = keychainManager.getAPIKey(for: testProvider)
        
        XCTAssertEqual(retrieved, testAPIKey, "Should retrieve saved API key")
    }
    
    func testRetrieveNonexistentKey() {
        let retrieved = keychainManager.getAPIKey(for: "NonexistentProvider")
        
        XCTAssertNil(retrieved, "Should return nil for nonexistent key")
    }
    
    func testSaveEmptyKey() {
        // Save empty key
        keychainManager.saveAPIKey("", for: testProvider)
        
        // Should still save it
        let retrieved = keychainManager.getAPIKey(for: testProvider)
        XCTAssertEqual(retrieved, "", "Should save and retrieve empty key")
    }
    
    // MARK: - Update Tests
    
    func testUpdateExistingKey() {
        // Save initial key
        keychainManager.saveAPIKey(testAPIKey, for: testProvider)
        
        // Update with new key
        let newKey = "updated-api-key-09876543210987654321"
        keychainManager.saveAPIKey(newKey, for: testProvider)
        
        // Verify update
        let retrieved = keychainManager.getAPIKey(for: testProvider)
        XCTAssertEqual(retrieved, newKey, "Should update existing key")
    }
    
    func testMultipleUpdates() {
        // Save and update multiple times
        for i in 1...5 {
            let key = "api-key-version-\(i)"
            keychainManager.saveAPIKey(key, for: testProvider)
            
            let retrieved = keychainManager.getAPIKey(for: testProvider)
            XCTAssertEqual(retrieved, key, "Should handle update \(i)")
        }
    }
    
    // MARK: - Delete Tests
    
    func testDeleteAPIKey() throws {
        // Save key
        keychainManager.saveAPIKey(testAPIKey, for: testProvider)
        XCTAssertNotNil(keychainManager.getAPIKey(for: testProvider))
        
        // Delete key
        try keychainManager.deleteAPIKey(for: testProvider)
        
        // Verify deletion
        XCTAssertNil(keychainManager.getAPIKey(for: testProvider), "Key should be deleted")
    }
    
    func testDeleteNonexistentKey() throws {
        // Should not throw when deleting nonexistent key
        try keychainManager.deleteAPIKey(for: "NonexistentProvider")
        
        // No crash = success
    }
    
    func testDeleteAllAPIKeys() throws {
        // Save multiple keys
        keychainManager.saveAPIKey("key1", for: "Provider1")
        keychainManager.saveAPIKey("key2", for: "Provider2")
        keychainManager.saveAPIKey("key3", for: "Provider3")
        
        // Delete all
        try keychainManager.deleteAllAPIKeys()
        
        // Verify all deleted
        XCTAssertNil(keychainManager.getAPIKey(for: "Provider1"))
        XCTAssertNil(keychainManager.getAPIKey(for: "Provider2"))
        XCTAssertNil(keychainManager.getAPIKey(for: "Provider3"))
    }
    
    // MARK: - OSStatus Error Handling Tests
    
    func testHandlesDuplicateItemError() {
        // This is handled internally by checking if key exists first
        keychainManager.saveAPIKey(testAPIKey, for: testProvider)
        
        // Save again (should update, not error)
        keychainManager.saveAPIKey(testAPIKey, for: testProvider)
        
        let retrieved = keychainManager.getAPIKey(for: testProvider)
        XCTAssertEqual(retrieved, testAPIKey, "Should handle duplicate save")
    }
    
    func testDeleteWithoutErrorWhenNotFound() throws {
        // Delete nonexistent key should not throw
        try keychainManager.deleteAPIKey(for: "NonexistentProvider")
        
        // No error = success
    }
    
    // MARK: - Multiple Provider Tests
    
    func testMultipleProviders() {
        let providers = ["OpenAI", "ElevenLabs", "Google", "Deepgram", "Groq"]
        
        // Save keys for all providers
        for (index, provider) in providers.enumerated() {
            let key = "api-key-\(provider)-\(index)"
            keychainManager.saveAPIKey(key, for: provider)
        }
        
        // Verify all keys
        for (index, provider) in providers.enumerated() {
            let expectedKey = "api-key-\(provider)-\(index)"
            let retrieved = keychainManager.getAPIKey(for: provider)
            XCTAssertEqual(retrieved, expectedKey, "Should retrieve key for \(provider)")
        }
    }
    
    func testGetAllProviders() {
        // Save keys for multiple providers
        keychainManager.saveAPIKey("key1", for: "Provider1")
        keychainManager.saveAPIKey("key2", for: "Provider2")
        keychainManager.saveAPIKey("key3", for: "Provider3")
        
        // Get all providers
        let providers = keychainManager.getAllProviders()
        
        XCTAssertEqual(providers.count, 3, "Should have 3 providers")
        XCTAssertTrue(providers.contains("Provider1"))
        XCTAssertTrue(providers.contains("Provider2"))
        XCTAssertTrue(providers.contains("Provider3"))
    }
    
    // MARK: - Key Existence Tests
    
    func testHasAPIKey() {
        XCTAssertFalse(keychainManager.hasAPIKey(for: testProvider), "Should not have key initially")
        
        keychainManager.saveAPIKey(testAPIKey, for: testProvider)
        
        XCTAssertTrue(keychainManager.hasAPIKey(for: testProvider), "Should have key after saving")
    }
    
    // MARK: - Validation Tests
    
    func testValidAPIKeyFormatOpenAI() {
        let validKey = "sk-proj-abcdefghijklmnopqrstuvwxyz1234567890ABCD"
        XCTAssertTrue(
            KeychainManager.isValidAPIKey(validKey, for: "OpenAI"),
            "Should validate OpenAI key format"
        )
        
        let invalidKey = "invalid-key"
        XCTAssertFalse(
            KeychainManager.isValidAPIKey(invalidKey, for: "OpenAI"),
            "Should reject invalid OpenAI key"
        )
    }
    
    func testValidAPIKeyFormatElevenLabs() {
        let validKey = String(repeating: "a", count: 32) // 32 alphanumeric chars
        XCTAssertTrue(
            KeychainManager.isValidAPIKey(validKey, for: "ElevenLabs"),
            "Should validate ElevenLabs key format"
        )
        
        let tooShort = "abc123"
        XCTAssertFalse(
            KeychainManager.isValidAPIKey(tooShort, for: "ElevenLabs"),
            "Should reject short key"
        )
    }
    
    func testValidAPIKeyFormatGoogle() {
        let validKey = "AIzaSyAbCdEfGhIjKlMnOpQrStUvWxYz123456"
        XCTAssertTrue(
            KeychainManager.isValidAPIKey(validKey, for: "Google"),
            "Should validate Google key format"
        )
    }
    
    func testGenericValidation() {
        // Keys must be 20-200 chars
        let tooShort = "abc"
        XCTAssertFalse(
            KeychainManager.isValidAPIKey(tooShort),
            "Should reject too short key"
        )
        
        let tooLong = String(repeating: "a", count: 201)
        XCTAssertFalse(
            KeychainManager.isValidAPIKey(tooLong),
            "Should reject too long key"
        )
        
        let validLength = String(repeating: "a", count: 50)
        XCTAssertTrue(
            KeychainManager.isValidAPIKey(validLength),
            "Should accept valid length key"
        )
    }
    
    // MARK: - Thread Safety Tests
    
    func testConcurrentSaveOperations() async {
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    let provider = "Provider\(i % 5)" // 5 different providers
                    let key = "key-\(i)"
                    self.keychainManager.saveAPIKey(key, for: provider)
                }
            }
            await group.waitForAll()
        }
        
        // Verify some keys were saved
        let providers = keychainManager.getAllProviders()
        XCTAssertGreaterThan(providers.count, 0, "Should save keys concurrently")
    }
    
    func testConcurrentReadOperations() async {
        // Save a key first
        keychainManager.saveAPIKey(testAPIKey, for: testProvider)
        
        // Read concurrently
        await withTaskGroup(of: String?.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    return self.keychainManager.getAPIKey(for: self.testProvider)
                }
            }
            
            var results: [String?] = []
            for await result in group {
                results.append(result)
            }
            
            // All reads should succeed
            XCTAssertEqual(results.count, 50)
            XCTAssertTrue(results.allSatisfy { $0 == self.testAPIKey })
        }
    }
    
    func testConcurrentDeleteOperations() async {
        // Save multiple keys
        for i in 0..<10 {
            keychainManager.saveAPIKey("key\(i)", for: "Provider\(i)")
        }
        
        // Delete concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    try? self.keychainManager.deleteAPIKey(for: "Provider\(i)")
                }
            }
            await group.waitForAll()
        }
        
        // Verify deletions
        let remaining = keychainManager.getAllProviders()
        XCTAssertEqual(remaining.count, 0, "All keys should be deleted")
    }
    
    // MARK: - Data Integrity Tests
    
    func testSaveSpecialCharacters() {
        let specialKey = "test!@#$%^&*()_+-=[]{}|;:',.<>?/~`"
        keychainManager.saveAPIKey(specialKey, for: testProvider)
        
        let retrieved = keychainManager.getAPIKey(for: testProvider)
        XCTAssertEqual(retrieved, specialKey, "Should handle special characters")
    }
    
    func testSaveUnicodeCharacters() {
        let unicodeKey = "test-🔑-emoji-키-中文"
        keychainManager.saveAPIKey(unicodeKey, for: testProvider)
        
        let retrieved = keychainManager.getAPIKey(for: testProvider)
        XCTAssertEqual(retrieved, unicodeKey, "Should handle unicode characters")
    }
    
    func testSaveLongKey() {
        let longKey = String(repeating: "a", count: 200) // Max length
        keychainManager.saveAPIKey(longKey, for: testProvider)
        
        let retrieved = keychainManager.getAPIKey(for: testProvider)
        XCTAssertEqual(retrieved, longKey, "Should handle long keys")
    }
    
    // MARK: - Persistence Tests
    
    func testKeyPersistsAcrossInstances() {
        // Save with first instance
        keychainManager.saveAPIKey(testAPIKey, for: testProvider)
        
        // Create new instance with same service
        let newManager = KeychainManager(service: "com.test.VoiceInk.KeychainTests")
        
        // Retrieve with new instance
        let retrieved = newManager.getAPIKey(for: testProvider)
        XCTAssertEqual(retrieved, testAPIKey, "Key should persist across instances")
        
        // Clean up
        try? newManager.deleteAPIKey(for: testProvider)
    }
    
    // MARK: - Migration Tests
    
    func testMigrateFromUserDefaults() {
        // Set up old-style keys in UserDefaults
        UserDefaults.standard.set("old-elevenlabs-key", forKey: "apiKey_ElevenLabs")
        UserDefaults.standard.set("old-openai-key", forKey: "apiKey_OpenAI")
        
        // Run migration
        keychainManager.migrateFromUserDefaults()
        
        // Verify keys were migrated to keychain
        XCTAssertEqual(
            keychainManager.getAPIKey(for: "ElevenLabs"),
            "old-elevenlabs-key",
            "Should migrate ElevenLabs key"
        )
        XCTAssertEqual(
            keychainManager.getAPIKey(for: "OpenAI"),
            "old-openai-key",
            "Should migrate OpenAI key"
        )
        
        // Verify keys were removed from UserDefaults
        XCTAssertNil(UserDefaults.standard.string(forKey: "apiKey_ElevenLabs"))
        XCTAssertNil(UserDefaults.standard.string(forKey: "apiKey_OpenAI"))
    }
}
