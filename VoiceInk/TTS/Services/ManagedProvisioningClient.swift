import Foundation

final class ManagedProvisioningClient {
    struct Configuration: Equatable {
        var baseURL: URL
        var accountId: String
        var planTier: String
        var planStatus: String
    }

    static let shared = ManagedProvisioningClient()

    private let preferences: ManagedProvisioningPreferences
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let lock = NSLock()
    private var credentialCache: [Voice.ProviderType: ManagedCredential] = [:]

    init(preferences: ManagedProvisioningPreferences = .shared,
         session: URLSession = SecureURLSession.makeEphemeral()) {
        self.preferences = preferences
        self.session = session
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        self.decoder = decoder
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        self.encoder = encoder
    }

    // MARK: - Preferences

    var configuration: Configuration? {
        get { preferences.currentConfiguration }
        set { preferences.currentConfiguration = newValue }
    }

    var isEnabled: Bool {
        get { preferences.isEnabled }
        set { preferences.isEnabled = newValue }
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        credentialCache.removeAll()
        preferences.clear()
    }

    func invalidateAllCredentials() {
        lock.lock(); defer { lock.unlock() }
        credentialCache.removeAll()
    }

    // MARK: - Account Snapshot

    func fetchAccountSnapshot() async throws -> ManagedAccountSnapshot {
        guard let config = configuration else {
            throw ProvisioningError.missingConfiguration
        }

        var request = URLRequest(url: config.baseURL.appendingPathComponent("api/account"))
        request.httpMethod = "GET"
        request.setValue(config.accountId, forHTTPHeaderField: "x-account-id")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ProvisioningError.invalidResponse
        }
        return try decoder.decode(ManagedAccountSnapshot.self, from: data)
    }

    // MARK: - Credential Handling

    func credential(for provider: Voice.ProviderType) async throws -> ManagedCredential? {
        guard isEnabled, let config = configuration else {
            return nil
        }

        if let cached = cachedCredential(for: provider), cached.expiresAt > Date() {
            return cached
        }

        var request = URLRequest(url: config.baseURL.appendingPathComponent("api/provisioning/token"))
        request.httpMethod = "POST"
        request.setValue(config.accountId, forHTTPHeaderField: "x-account-id")
        request.setValue(config.planTier.isEmpty ? "starter" : config.planTier, forHTTPHeaderField: "x-plan-tier")
        request.setValue(config.planStatus.isEmpty ? "active" : config.planStatus, forHTTPHeaderField: "x-plan-status")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: String] = ["provider": provider.rawValue.lowercased()]
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            invalidateCredential(for: provider)
            throw ProvisioningError.invalidResponse
        }

        let credential = try decoder.decode(ManagedCredential.self, from: data)
        cache(credential: credential, for: provider)
        return credential
    }

    func invalidateCredential(for provider: Voice.ProviderType) {
        lock.lock(); defer { lock.unlock() }
        credentialCache.removeValue(forKey: provider)
    }

    private func cachedCredential(for provider: Voice.ProviderType) -> ManagedCredential? {
        lock.lock(); defer { lock.unlock() }
        return credentialCache[provider]
    }

    private func cache(credential: ManagedCredential, for provider: Voice.ProviderType) {
        lock.lock(); defer { lock.unlock() }
        credentialCache[provider] = credential
    }

    enum ProvisioningError: Error, LocalizedError {
        case missingConfiguration
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .missingConfiguration:
                return "Managed provisioning configuration is missing."
            case .invalidResponse:
                return "Managed provisioning service returned an unexpected response."
            }
        }
    }
}

extension ManagedProvisioningClient: @unchecked Sendable {}
