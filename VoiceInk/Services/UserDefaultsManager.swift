import Foundation

extension UserDefaults {
    enum Keys {
        static let audioInputMode = "audioInputMode"
        static let selectedAudioDeviceUID = "selectedAudioDeviceUID"
        static let prioritizedDevices = "prioritizedDevices"
        static let affiliatePromotionDismissed = "VoiceInkAffiliatePromotionDismissed"
        static let activationShortcutProfiles = "activationShortcutProfiles"
        static let activeActivationShortcutProfileID = "activeActivationShortcutProfileID"
        static let shortcutProfilesEnabled = "shortcutProfilesEnabled"
        static let legacyToggleMiniRecorderShortcut = "legacyToggleMiniRecorderShortcut"
        static let legacyToggleMiniRecorderShortcut2 = "legacyToggleMiniRecorderShortcut2"
    }

    // MARK: - Audio Input Mode
    var audioInputModeRawValue: String? {
        get { string(forKey: Keys.audioInputMode) }
        set { setValue(newValue, forKey: Keys.audioInputMode) }
    }

    // MARK: - Selected Audio Device UID
    var selectedAudioDeviceUID: String? {
        get { string(forKey: Keys.selectedAudioDeviceUID) }
        set { setValue(newValue, forKey: Keys.selectedAudioDeviceUID) }
    }

    // MARK: - Prioritized Devices
    var prioritizedDevicesData: Data? {
        get { data(forKey: Keys.prioritizedDevices) }
        set { setValue(newValue, forKey: Keys.prioritizedDevices) }
    }

    // MARK: - Affiliate Promotion Dismissal
    var affiliatePromotionDismissed: Bool {
        get { bool(forKey: Keys.affiliatePromotionDismissed) }
        set { setValue(newValue, forKey: Keys.affiliatePromotionDismissed) }
    }

    // MARK: - Activation Shortcut Profiles
    var activationShortcutProfilesData: Data? {
        get { data(forKey: Keys.activationShortcutProfiles) }
        set { setValue(newValue, forKey: Keys.activationShortcutProfiles) }
    }

    var activeActivationShortcutProfileID: String? {
        get { string(forKey: Keys.activeActivationShortcutProfileID) }
        set { setValue(newValue, forKey: Keys.activeActivationShortcutProfileID) }
    }

    var shortcutProfilesEnabled: Bool {
        get { bool(forKey: Keys.shortcutProfilesEnabled) }
        set { setValue(newValue, forKey: Keys.shortcutProfilesEnabled) }
    }

    var legacyToggleMiniRecorderShortcutData: Data? {
        get { data(forKey: Keys.legacyToggleMiniRecorderShortcut) }
        set { setValue(newValue, forKey: Keys.legacyToggleMiniRecorderShortcut) }
    }

    var legacyToggleMiniRecorderShortcut2Data: Data? {
        get { data(forKey: Keys.legacyToggleMiniRecorderShortcut2) }
        set { setValue(newValue, forKey: Keys.legacyToggleMiniRecorderShortcut2) }
    }
}
