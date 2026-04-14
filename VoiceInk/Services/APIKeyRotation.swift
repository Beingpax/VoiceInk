import Foundation
import os

/// A single API key entry for a provider. Multiple entries per provider enable
/// auto-rotation when one key hits quota / auth errors.
struct APIKeyEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var label: String
    var key: String
    var disabled: Bool
    var lastFailureAt: Date?
    var lastFailureReason: String?

    init(
        id: UUID = UUID(),
        label: String,
        key: String,
        disabled: Bool = false,
        lastFailureAt: Date? = nil,
        lastFailureReason: String? = nil
    ) {
        self.id = id
        self.label = label
        self.key = key
        self.disabled = disabled
        self.lastFailureAt = lastFailureAt
        self.lastFailureReason = lastFailureReason
    }
}

/// Classifies an error as either a "key-level" failure (rotate) or a transient
/// failure (do not rotate). Used by streaming and batch retry loops.
enum APIKeyFailureClass {
    /// Unambiguous key problem: auth, quota, rate-limited, forbidden.
    case keyLevel(reason: String)
    /// Transient or non-key failure: network, 5xx, timeout.
    case transient(reason: String)

    /// ElevenLabs-specific WebSocket error keywords that indicate a key-level failure.
    static let elevenLabsKeyLevelKeywords: [String] = [
        "auth_error",
        "quota_exceeded",
        "rate_limited",
        "resource_exhausted",
        "unauthorized",
        "invalid_api_key",
        "invalid api key"
    ]

    /// HTTP status codes that indicate a key-level failure across providers.
    static let keyLevelHTTPStatusCodes: Set<Int> = [401, 402, 403, 429]

    /// Classifies an ElevenLabs WebSocket error message string.
    static func classifyElevenLabsWSError(_ message: String) -> APIKeyFailureClass {
        let lowered = message.lowercased()
        for keyword in elevenLabsKeyLevelKeywords where lowered.contains(keyword) {
            return .keyLevel(reason: message)
        }
        return .transient(reason: message)
    }

    /// Classifies an HTTP status code + message into a failure class.
    static func classifyHTTP(statusCode: Int, message: String) -> APIKeyFailureClass {
        if keyLevelHTTPStatusCodes.contains(statusCode) {
            return .keyLevel(reason: "HTTP \(statusCode): \(message)")
        }
        return .transient(reason: "HTTP \(statusCode): \(message)")
    }
}

/// Multi-key rotation extensions on APIKeyManager.
extension APIKeyManager {

    private static let rotationLogger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "APIKeyRotation"
    )

    // MARK: - Keychain / UserDefaults identifier helpers

    /// Keychain identifier that holds the JSON-encoded `[APIKeyEntry]` for a provider.
    fileprivate static func multiKeyKeychainIdentifier(forProvider provider: String) -> String {
        "\(provider.lowercased())APIKeys_v1"
    }

    /// UserDefaults key that persists the active rotation index for a provider.
    fileprivate static func activeIndexDefaultsKey(forProvider provider: String) -> String {
        "APIKeyRotation_activeIndex_\(provider.lowercased())"
    }

    // MARK: - Public multi-key API

    /// Returns all keys for a provider. Auto-migrates a legacy single key if the
    /// multi-key store is empty but a legacy key exists.
    func getAPIKeys(forProvider provider: String) -> [APIKeyEntry] {
        let identifier = Self.multiKeyKeychainIdentifier(forProvider: provider)

        if let data = KeychainService.shared.getData(forKey: identifier),
           let decoded = try? JSONDecoder().decode([APIKeyEntry].self, from: data) {
            return decoded
        }

        // Legacy migration path: pull the old single key (if any) into a new
        // single-entry array without deleting the legacy record, so failed
        // migrations don't lose data.
        if let legacyKey = getAPIKey(forProvider: provider), !legacyKey.isEmpty {
            let migrated = [APIKeyEntry(label: "Primary", key: legacyKey)]
            if saveAPIKeysInternal(migrated, forProvider: provider) {
                Self.rotationLogger.info(
                    "Migrated legacy single key to multi-key store for provider: \(provider, privacy: .public)"
                )
            }
            return migrated
        }

        return []
    }

    /// Persists the full list of keys for a provider. Returns true on success.
    /// Also keeps the legacy single-key Keychain entry in sync with the currently
    /// active key so unchanged call sites (`getAPIKey(forProvider:)`) keep working.
    @discardableResult
    func saveAPIKeys(_ keys: [APIKeyEntry], forProvider provider: String) -> Bool {
        guard saveAPIKeysInternal(keys, forProvider: provider) else { return false }
        clampActiveIndex(forProvider: provider)
        syncLegacyActiveKey(forProvider: provider)
        return true
    }

    /// Adds a new key entry. Returns the created entry. Duplicate raw keys are
    /// silently ignored (returns nil) so the user can't add the same key twice.
    @discardableResult
    func addAPIKey(_ key: String, label: String, forProvider provider: String) -> APIKeyEntry? {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return nil }

        var existing = getAPIKeys(forProvider: provider)
        if existing.contains(where: { $0.key == trimmedKey }) {
            return nil
        }

        let entry = APIKeyEntry(
            label: trimmedLabel.isEmpty ? defaultLabel(forIndex: existing.count) : trimmedLabel,
            key: trimmedKey
        )
        existing.append(entry)
        guard saveAPIKeys(existing, forProvider: provider) else { return nil }
        return entry
    }

    /// Removes a key by id. Adjusts the active index so it still points at a
    /// valid entry (or 0 if the list is now empty).
    @discardableResult
    func removeAPIKey(id: UUID, forProvider provider: String) -> Bool {
        var existing = getAPIKeys(forProvider: provider)
        guard let removedIndex = existing.firstIndex(where: { $0.id == id }) else { return false }

        existing.remove(at: removedIndex)

        let currentIndex = activeIndex(forProvider: provider)
        let newIndex: Int
        if existing.isEmpty {
            newIndex = 0
        } else if removedIndex < currentIndex {
            newIndex = currentIndex - 1
        } else if removedIndex == currentIndex {
            newIndex = currentIndex % existing.count
        } else {
            newIndex = currentIndex
        }
        setActiveIndex(newIndex, forProvider: provider)

        // If we just emptied the list, also clear the legacy single-key entry
        // so stale data doesn't leak into unchanged call sites.
        if existing.isEmpty {
            deleteAPIKey(forProvider: provider)
            KeychainService.shared.delete(forKey: Self.multiKeyKeychainIdentifier(forProvider: provider))
            UserDefaults.standard.removeObject(forKey: Self.activeIndexDefaultsKey(forProvider: provider))
            return true
        }

        return saveAPIKeys(existing, forProvider: provider)
    }

    /// Updates label / disabled / failure fields on an existing entry. The raw
    /// key value is not replaced here (use remove + add for that, so verification
    /// is re-run by the UI).
    @discardableResult
    func updateAPIKey(
        id: UUID,
        label: String? = nil,
        disabled: Bool? = nil,
        clearFailure: Bool = false,
        forProvider provider: String
    ) -> Bool {
        var existing = getAPIKeys(forProvider: provider)
        guard let idx = existing.firstIndex(where: { $0.id == id }) else { return false }

        if let label = label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            existing[idx].label = label
        }
        if let disabled = disabled {
            existing[idx].disabled = disabled
        }
        if clearFailure {
            existing[idx].lastFailureAt = nil
            existing[idx].lastFailureReason = nil
        }

        return saveAPIKeys(existing, forProvider: provider)
    }

    /// Returns the currently active enabled key entry, or nil if none is usable.
    /// Automatically advances past disabled entries (without mutating state) when
    /// the stored active index happens to land on one.
    func activeAPIKey(forProvider provider: String) -> APIKeyEntry? {
        let keys = getAPIKeys(forProvider: provider)
        guard !keys.isEmpty else { return nil }

        let startIndex = activeIndex(forProvider: provider) % keys.count
        for offset in 0..<keys.count {
            let idx = (startIndex + offset) % keys.count
            if !keys[idx].disabled {
                return keys[idx]
            }
        }
        return nil
    }

    /// Advances the active index to the next enabled key, skipping disabled
    /// entries. Marks the currently-active key as failed with the given reason.
    /// Returns the new active entry (nil if no enabled keys remain).
    @discardableResult
    func rotateToNextKey(forProvider provider: String, reason: String) -> APIKeyEntry? {
        var keys = getAPIKeys(forProvider: provider)
        guard !keys.isEmpty else { return nil }

        let currentIndex = activeIndex(forProvider: provider) % keys.count

        // Stamp failure on the key we're rotating AWAY from, if it was enabled.
        if !keys[currentIndex].disabled {
            keys[currentIndex].lastFailureAt = Date()
            keys[currentIndex].lastFailureReason = reason
        }

        // Find the next enabled index after currentIndex.
        var nextIndex: Int? = nil
        for offset in 1...keys.count {
            let idx = (currentIndex + offset) % keys.count
            if idx == currentIndex { break } // wrapped fully, no other enabled
            if !keys[idx].disabled {
                nextIndex = idx
                break
            }
        }

        saveAPIKeysInternal(keys, forProvider: provider)

        guard let nextIndex = nextIndex else {
            // Only the current (now-marked-failed) key is enabled — no rotation possible.
            Self.rotationLogger.warning(
                "No alternate enabled key available for provider: \(provider, privacy: .public)"
            )
            syncLegacyActiveKey(forProvider: provider)
            return nil
        }

        setActiveIndex(nextIndex, forProvider: provider)
        syncLegacyActiveKey(forProvider: provider)

        Self.rotationLogger.notice(
            "Rotated API key for provider \(provider, privacy: .public): \(keys[currentIndex].label, privacy: .public) → \(keys[nextIndex].label, privacy: .public) (reason: \(reason, privacy: .public))"
        )

        return keys[nextIndex]
    }

    /// Marks a specific key entry as having failed with a reason, without
    /// rotating. Useful when the failure is surfaced mid-session and we want the
    /// *next* session to rotate automatically.
    @discardableResult
    func markKeyFailed(id: UUID, reason: String, forProvider provider: String) -> Bool {
        var keys = getAPIKeys(forProvider: provider)
        guard let idx = keys.firstIndex(where: { $0.id == id }) else { return false }
        keys[idx].lastFailureAt = Date()
        keys[idx].lastFailureReason = reason
        return saveAPIKeys(keys, forProvider: provider)
    }

    /// Sets the active index to a specific key id, if it exists and is enabled.
    @discardableResult
    func setActiveKey(id: UUID, forProvider provider: String) -> Bool {
        let keys = getAPIKeys(forProvider: provider)
        guard let idx = keys.firstIndex(where: { $0.id == id }), !keys[idx].disabled else {
            return false
        }
        setActiveIndex(idx, forProvider: provider)
        syncLegacyActiveKey(forProvider: provider)
        return true
    }

    /// Returns how many keys are present + how many are currently enabled.
    func apiKeyCounts(forProvider provider: String) -> (total: Int, enabled: Int) {
        let keys = getAPIKeys(forProvider: provider)
        return (keys.count, keys.filter { !$0.disabled }.count)
    }

    // MARK: - Private

    @discardableResult
    private func saveAPIKeysInternal(_ keys: [APIKeyEntry], forProvider provider: String) -> Bool {
        let identifier = Self.multiKeyKeychainIdentifier(forProvider: provider)

        if keys.isEmpty {
            return KeychainService.shared.delete(forKey: identifier)
        }

        do {
            let data = try JSONEncoder().encode(keys)
            return KeychainService.shared.save(data: data, forKey: identifier)
        } catch {
            Self.rotationLogger.error(
                "Failed to encode APIKeyEntry array for provider \(provider, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    /// Keeps the legacy single-key Keychain entry in sync with the currently
    /// active multi-key entry. This preserves backward-compat for every call
    /// site that reads via `getAPIKey(forProvider:)`. When no enabled key
    /// exists, the legacy entry is cleared so callers see the same
    /// "no key configured" state the multi-key UI shows.
    private func syncLegacyActiveKey(forProvider provider: String) {
        if let active = activeAPIKey(forProvider: provider), !active.key.isEmpty {
            saveAPIKey(active.key, forProvider: provider)
        } else {
            deleteAPIKey(forProvider: provider)
        }
    }

    private func activeIndex(forProvider provider: String) -> Int {
        let raw = UserDefaults.standard.integer(forKey: Self.activeIndexDefaultsKey(forProvider: provider))
        return max(0, raw)
    }

    private func setActiveIndex(_ index: Int, forProvider provider: String) {
        UserDefaults.standard.set(max(0, index), forKey: Self.activeIndexDefaultsKey(forProvider: provider))
    }

    private func clampActiveIndex(forProvider provider: String) {
        let keys = getAPIKeys(forProvider: provider)
        let current = activeIndex(forProvider: provider)
        if keys.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.activeIndexDefaultsKey(forProvider: provider))
            return
        }
        if current >= keys.count {
            setActiveIndex(0, forProvider: provider)
        }
    }

    private func defaultLabel(forIndex index: Int) -> String {
        "Key \(index + 1)"
    }
}
