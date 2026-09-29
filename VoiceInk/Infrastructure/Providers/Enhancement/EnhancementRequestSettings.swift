import Foundation

enum EnhancementRequestSettings {
    static let timeoutKey = "EnhancementTimeoutSeconds"
    static let retryOnTimeoutKey = "EnhancementRetryOnTimeout"
    static let defaultTimeoutSeconds = 7
    static let defaultRetryOnTimeout = true
    static let maximumAttempts = 3

    static var timeout: TimeInterval {
        let configuredTimeout = UserDefaults.standard.integer(forKey: timeoutKey)
        return TimeInterval(configuredTimeout > 0 ? configuredTimeout : defaultTimeoutSeconds)
    }

    static var retryOnTimeout: Bool {
        guard UserDefaults.standard.object(forKey: retryOnTimeoutKey) != nil else {
            return defaultRetryOnTimeout
        }
        return UserDefaults.standard.bool(forKey: retryOnTimeoutKey)
    }
}
