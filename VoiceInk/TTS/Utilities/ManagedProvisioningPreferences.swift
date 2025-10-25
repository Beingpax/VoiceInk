import Foundation

final class ManagedProvisioningPreferences {
    static let shared = ManagedProvisioningPreferences()

    private enum Keys {
        static let baseURL = "managedProvisioning.baseURL"
        static let accountId = "managedProvisioning.accountId"
        static let planTier = "managedProvisioning.planTier"
        static let planStatus = "managedProvisioning.planStatus"
        static let isEnabled = "managedProvisioning.enabled"
    }

    var currentConfiguration: ManagedProvisioningClient.Configuration? {
        get {
            guard let urlString = UserDefaults.standard.string(forKey: Keys.baseURL),
                  let url = URL(string: urlString),
                  let accountId = UserDefaults.standard.string(forKey: Keys.accountId),
                  let planTier = UserDefaults.standard.string(forKey: Keys.planTier),
                  let planStatus = UserDefaults.standard.string(forKey: Keys.planStatus) else {
                return nil
            }
            return .init(baseURL: url, accountId: accountId, planTier: planTier, planStatus: planStatus)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.baseURL.absoluteString, forKey: Keys.baseURL)
                UserDefaults.standard.set(newValue.accountId, forKey: Keys.accountId)
                UserDefaults.standard.set(newValue.planTier, forKey: Keys.planTier)
                UserDefaults.standard.set(newValue.planStatus, forKey: Keys.planStatus)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.baseURL)
                UserDefaults.standard.removeObject(forKey: Keys.accountId)
                UserDefaults.standard.removeObject(forKey: Keys.planTier)
                UserDefaults.standard.removeObject(forKey: Keys.planStatus)
            }
        }
    }

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Keys.isEnabled) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: Keys.isEnabled) }
    }

    func clear() {
        currentConfiguration = nil
        isEnabled = false
    }
}

extension ManagedProvisioningPreferences: @unchecked Sendable {}
