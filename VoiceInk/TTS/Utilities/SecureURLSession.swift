import Foundation

/// Factory for URLSession instances configured to avoid persisting sensitive data.
enum SecureURLSession {
    /// Returns an ephemeral session that disables persistent cookies and on-disk caching.
    /// - Parameter configure: Optional hook for callers that need further customization.
    static func makeEphemeral(configure: ((URLSessionConfiguration) -> Void)? = nil) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configure?(configuration)
        return URLSession(configuration: configuration)
    }
}
