import Foundation

/// Central place for user-editable app configuration values.
enum AppConfiguration {
    /// Update with your GitHub Sponsors profile URL (e.g. https://github.com/sponsors/your-username).
    static let donationURL: URL? = nil

    /// Link to product documentation (defaults to the repository README).
    static let documentationURL = URL(string: "https://github.com/Beingpax/VoiceInk")

    /// Issue tracker for bug reports and feature requests.
    static let issueTrackerURL = URL(string: "https://github.com/Beingpax/VoiceInk/issues")

    /// Public privacy statement.
    static let privacyPolicyURL: URL? = nil
}
