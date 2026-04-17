import Testing
import Foundation
@testable import VoiceInk

/// Tests for multi-API-key rotation. Uses unique per-test provider keys so
/// parallel runs never collide on shared Keychain/UserDefaults state.
struct APIKeyRotationTests {

    /// Produces a unique provider key for each test so state is isolated.
    /// A `_test_` prefix prevents any accidental collision with real providers.
    private func makeProviderKey(_ suffix: String = #function) -> String {
        // #function includes parentheses like "testAddKey()" — strip them and
        // add a UUID so re-runs within the same process don't see stale state.
        let clean = suffix
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
        return "_test_\(clean)_\(UUID().uuidString)"
    }

    private func cleanup(_ provider: String) {
        let manager = APIKeyManager.shared
        for entry in manager.getAPIKeys(forProvider: provider) {
            manager.removeAPIKey(id: entry.id, forProvider: provider)
        }
        manager.deleteAPIKey(forProvider: provider)
    }

    // MARK: - Basic CRUD

    @Test func addKeyCreatesEntry() {
        let provider = makeProviderKey()
        defer { cleanup(provider) }
        let manager = APIKeyManager.shared

        let entry = manager.addAPIKey("sk-aaa", label: "First", forProvider: provider)

        #expect(entry != nil)
        #expect(entry?.label == "First")
        #expect(entry?.disabled == false)
        #expect(manager.getAPIKeys(forProvider: provider).count == 1)
    }

    @Test func addKeyUsesDefaultLabelWhenBlank() {
        let provider = makeProviderKey()
        defer { cleanup(provider) }
        let manager = APIKeyManager.shared

        _ = manager.addAPIKey("sk-aaa", label: "", forProvider: provider)
        _ = manager.addAPIKey("sk-bbb", label: "", forProvider: provider)

        let keys = manager.getAPIKeys(forProvider: provider)
        #expect(keys[0].label == "Key 1")
        #expect(keys[1].label == "Key 2")
    }

    @Test func addKeyRejectsEmptyKey() {
        let provider = makeProviderKey()
        defer { cleanup(provider) }
        let manager = APIKeyManager.shared

        #expect(manager.addAPIKey("   ", label: "blank", forProvider: provider) == nil)
        #expect(manager.getAPIKeys(forProvider: provider).isEmpty)
    }

    @Test func addKeyRejectsDuplicate() {
        let provider = makeProviderKey()
        defer { cleanup(provider) }
        let manager = APIKeyManager.shared

        let first = manager.addAPIKey("sk-dup", label: "A", forProvider: provider)
        let duplicate = manager.addAPIKey("sk-dup", label: "B", forProvider: provider)

        #expect(first != nil)
        #expect(duplicate == nil)
        #expect(manager.getAPIKeys(forProvider: provider).count == 1)
    }

    @Test func removeKeyAdjustsActiveIndex() {
        let provider = makeProviderKey()
        defer { cleanup(provider) }
        let manager = APIKeyManager.shared

        let k1 = manager.addAPIKey("sk-1", label: "One", forProvider: provider)!
        let k2 = manager.addAPIKey("sk-2", label: "Two", forProvider: provider)!
        let k3 = manager.addAPIKey("sk-3", label: "Three", forProvider: provider)!

        // Make k2 the active one.
        _ = manager.setActiveKey(id: k2.id, forProvider: provider)
        #expect(manager.activeAPIKey(forProvider: provider)?.id == k2.id)

        // Removing the active key should move activation to the next enabled entry.
        _ = manager.removeAPIKey(id: k2.id, forProvider: provider)
        let remaining = manager.getAPIKeys(forProvider: provider)
        #expect(remaining.count == 2)
        // Active should now be one of the survivors (k1 or k3), not nil.
        #expect(manager.activeAPIKey(forProvider: provider) != nil)

        // Removing a key BEFORE the active index should keep the same active entry.
        _ = manager.setActiveKey(id: k3.id, forProvider: provider)
        _ = manager.removeAPIKey(id: k1.id, forProvider: provider)
        #expect(manager.activeAPIKey(forProvider: provider)?.id == k3.id)
    }

    @Test func removeLastKeyClearsEverything() {
        let provider = makeProviderKey()
        defer { cleanup(provider) }
        let manager = APIKeyManager.shared

        let k = manager.addAPIKey("sk-only", label: "Only", forProvider: provider)!
        _ = manager.removeAPIKey(id: k.id, forProvider: provider)

        #expect(manager.getAPIKeys(forProvider: provider).isEmpty)
        #expect(manager.activeAPIKey(forProvider: provider) == nil)
        #expect(manager.getAPIKey(forProvider: provider) == nil)
    }

    // MARK: - Rotation

    @Test func rotateAdvancesAndSkipsDisabled() {
        let provider = makeProviderKey()
        defer { cleanup(provider) }
        let manager = APIKeyManager.shared

        let k1 = manager.addAPIKey("sk-1", label: "One", forProvider: provider)!
        let k2 = manager.addAPIKey("sk-2", label: "Two", forProvider: provider)!
        let k3 = manager.addAPIKey("sk-3", label: "Three", forProvider: provider)!

        // Disable k2 so rotation should skip over it.
        _ = manager.updateAPIKey(id: k2.id, disabled: true, forProvider: provider)

        // Start on k1, rotate → should land on k3 (k2 skipped).
        _ = manager.setActiveKey(id: k1.id, forProvider: provider)
        let next = manager.rotateToNextKey(forProvider: provider, reason: "test")
        #expect(next?.id == k3.id)
        #expect(manager.activeAPIKey(forProvider: provider)?.id == k3.id)

        // The key we rotated AWAY from should have a failure stamp now.
        let updated = manager.getAPIKeys(forProvider: provider).first(where: { $0.id == k1.id })!
        #expect(updated.lastFailureReason == "test")
        #expect(updated.lastFailureAt != nil)
    }

    @Test func rotateWrapsAround() {
        let provider = makeProviderKey()
        defer { cleanup(provider) }
        let manager = APIKeyManager.shared

        let k1 = manager.addAPIKey("sk-1", label: "One", forProvider: provider)!
        let k2 = manager.addAPIKey("sk-2", label: "Two", forProvider: provider)!

        _ = manager.setActiveKey(id: k2.id, forProvider: provider)
        let next = manager.rotateToNextKey(forProvider: provider, reason: "wrap")
        #expect(next?.id == k1.id)
    }

    @Test func rotateReturnsNilWhenOnlyOneEnabledKey() {
        let provider = makeProviderKey()
        defer { cleanup(provider) }
        let manager = APIKeyManager.shared

        let k1 = manager.addAPIKey("sk-1", label: "One", forProvider: provider)!
        let k2 = manager.addAPIKey("sk-2", label: "Two", forProvider: provider)!
        _ = manager.updateAPIKey(id: k2.id, disabled: true, forProvider: provider)

        _ = manager.setActiveKey(id: k1.id, forProvider: provider)
        let next = manager.rotateToNextKey(forProvider: provider, reason: "exhausted")
        #expect(next == nil)
        // The stale/disabled key should NOT be returned by activeAPIKey either,
        // because it's disabled; but since k1 is still enabled and was the only
        // option, activeAPIKey will still return k1 even though it's marked failed.
        let active = manager.activeAPIKey(forProvider: provider)
        #expect(active?.id == k1.id)
    }

    @Test func activeKeyReturnsNilWhenAllDisabled() {
        let provider = makeProviderKey()
        defer { cleanup(provider) }
        let manager = APIKeyManager.shared

        let k1 = manager.addAPIKey("sk-1", label: "One", forProvider: provider)!
        let k2 = manager.addAPIKey("sk-2", label: "Two", forProvider: provider)!
        _ = manager.updateAPIKey(id: k1.id, disabled: true, forProvider: provider)
        _ = manager.updateAPIKey(id: k2.id, disabled: true, forProvider: provider)

        #expect(manager.activeAPIKey(forProvider: provider) == nil)
    }

    // MARK: - Legacy migration + backward compatibility

    @Test func legacyKeyIsMigratedOnFirstRead() {
        let provider = makeProviderKey()
        defer { cleanup(provider) }
        let manager = APIKeyManager.shared

        // Seed a legacy single key via the old single-key API, bypassing the
        // multi-key store.
        _ = manager.saveAPIKey("legacy-key", forProvider: provider)

        let keys = manager.getAPIKeys(forProvider: provider)
        #expect(keys.count == 1)
        #expect(keys.first?.label == "Primary")
        #expect(keys.first?.key == "legacy-key")
    }

    @Test func getAPIKeyReturnsActiveKeyForLegacyCallers() {
        let provider = makeProviderKey()
        defer { cleanup(provider) }
        let manager = APIKeyManager.shared

        let k1 = manager.addAPIKey("sk-1", label: "One", forProvider: provider)!
        _ = manager.addAPIKey("sk-2", label: "Two", forProvider: provider)!

        _ = manager.setActiveKey(id: k1.id, forProvider: provider)
        #expect(manager.getAPIKey(forProvider: provider) == "sk-1")

        _ = manager.rotateToNextKey(forProvider: provider, reason: "rotate")
        #expect(manager.getAPIKey(forProvider: provider) == "sk-2")
    }

    // MARK: - Failure classification

    @Test func classifyHTTP401IsKeyLevel() {
        let result = APIKeyFailureClass.classifyHTTP(statusCode: 401, message: "Unauthorized")
        switch result {
        case .keyLevel: break // expected
        case .transient: Issue.record("401 should be key-level")
        }
    }

    @Test func classifyHTTP429IsKeyLevel() {
        let result = APIKeyFailureClass.classifyHTTP(statusCode: 429, message: "Too many requests")
        switch result {
        case .keyLevel: break
        case .transient: Issue.record("429 should be key-level")
        }
    }

    @Test func classifyHTTP500IsTransient() {
        let result = APIKeyFailureClass.classifyHTTP(statusCode: 500, message: "server")
        switch result {
        case .transient: break
        case .keyLevel: Issue.record("500 should be transient")
        }
    }

    @Test func classifyElevenLabsQuotaExceededIsKeyLevel() {
        let result = APIKeyFailureClass.classifyElevenLabsWSError("quota_exceeded: monthly limit reached")
        switch result {
        case .keyLevel: break
        case .transient: Issue.record("quota_exceeded should be key-level")
        }
    }

    @Test func classifyElevenLabsGenericErrorIsTransient() {
        let result = APIKeyFailureClass.classifyElevenLabsWSError("network disruption")
        switch result {
        case .transient: break
        case .keyLevel: Issue.record("generic network error should be transient")
        }
    }

    @Test func classifyElevenLabsAuthErrorCaseInsensitive() {
        let result = APIKeyFailureClass.classifyElevenLabsWSError("AUTH_ERROR: bad token")
        switch result {
        case .keyLevel: break
        case .transient: Issue.record("auth_error matching must be case-insensitive")
        }
    }

    // MARK: - Counts

    @Test func apiKeyCountsReflectsEnabledAndDisabled() {
        let provider = makeProviderKey()
        defer { cleanup(provider) }
        let manager = APIKeyManager.shared

        let k1 = manager.addAPIKey("sk-1", label: "One", forProvider: provider)!
        _ = manager.addAPIKey("sk-2", label: "Two", forProvider: provider)
        _ = manager.addAPIKey("sk-3", label: "Three", forProvider: provider)
        _ = manager.updateAPIKey(id: k1.id, disabled: true, forProvider: provider)

        let counts = manager.apiKeyCounts(forProvider: provider)
        #expect(counts.total == 3)
        #expect(counts.enabled == 2)
    }

    @Test func markKeyFailedPersistsReasonWithoutRotating() {
        let provider = makeProviderKey()
        defer { cleanup(provider) }
        let manager = APIKeyManager.shared

        let k1 = manager.addAPIKey("sk-1", label: "One", forProvider: provider)!
        _ = manager.addAPIKey("sk-2", label: "Two", forProvider: provider)
        _ = manager.setActiveKey(id: k1.id, forProvider: provider)

        _ = manager.markKeyFailed(id: k1.id, reason: "429", forProvider: provider)

        let updated = manager.getAPIKeys(forProvider: provider).first(where: { $0.id == k1.id })!
        #expect(updated.lastFailureReason == "429")
        // Active key should NOT have changed — markKeyFailed doesn't rotate.
        #expect(manager.activeAPIKey(forProvider: provider)?.id == k1.id)
    }
}
