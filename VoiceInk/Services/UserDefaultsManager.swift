import Foundation

extension UserDefaults {
    enum Keys {
        static let aiProviderApiKey = "VoiceInkAIProviderKey"
        static let licenseKey = "VoiceInkLicense"
        static let trialStartDate = "VoiceInkTrialStartDate"
        static let audioInputMode = "audioInputMode"
        static let selectedAudioDeviceUID = "selectedAudioDeviceUID"
        static let prioritizedDevices = "prioritizedDevices"
        static let affiliatePromotionDismissed = "VoiceInkAffiliatePromotionDismissed"

        // Multi-channel recording settings
        static let audioChannelMode = "audioChannelMode"
        static let audioCustomChannelCount = "audioCustomChannelCount"
        static let autoDownmixForTranscription = "autoDownmixForTranscription"

        // Obfuscated keys for license-related data
        enum License {
            static let trialStartDate = "VoiceInkTrialStartDate"
        }
    }
    
    // MARK: - AI Provider API Key
    var aiProviderApiKey: String? {
        get { string(forKey: Keys.aiProviderApiKey) }
        set { setValue(newValue, forKey: Keys.aiProviderApiKey) }
    }
    
    // MARK: - License Key
    var licenseKey: String? {
        get { string(forKey: Keys.licenseKey) }
        set { setValue(newValue, forKey: Keys.licenseKey) }
    }
    
    // MARK: - Trial Start Date (Obfuscated)
    var trialStartDate: Date? {
        get {
            let salt = Obfuscator.getDeviceIdentifier()
            let obfuscatedKey = Obfuscator.encode(Keys.License.trialStartDate, salt: salt)
            
            guard let obfuscatedValue = string(forKey: obfuscatedKey),
                  let decodedValue = Obfuscator.decode(obfuscatedValue, salt: salt),
                  let timestamp = Double(decodedValue) else {
                return nil
            }
            
            return Date(timeIntervalSince1970: timestamp)
        }
        set {
            let salt = Obfuscator.getDeviceIdentifier()
            let obfuscatedKey = Obfuscator.encode(Keys.License.trialStartDate, salt: salt)
            
            if let date = newValue {
                let timestamp = String(date.timeIntervalSince1970)
                let obfuscatedValue = Obfuscator.encode(timestamp, salt: salt)
                setValue(obfuscatedValue, forKey: obfuscatedKey)
            } else {
                removeObject(forKey: obfuscatedKey)
            }
        }
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

    // MARK: - Multi-Channel Recording Settings
    var audioChannelMode: String? {
        get { string(forKey: Keys.audioChannelMode) }
        set { setValue(newValue, forKey: Keys.audioChannelMode) }
    }

    var audioCustomChannelCount: Int {
        get {
            let count = integer(forKey: Keys.audioCustomChannelCount)
            return count == 0 ? 2 : count  // Default to 2 if not set
        }
        set { setValue(newValue, forKey: Keys.audioCustomChannelCount) }
    }

    var autoDownmixForTranscription: Bool {
        get {
            // Default to true if not explicitly set
            if object(forKey: Keys.autoDownmixForTranscription) == nil {
                return true
            }
            return bool(forKey: Keys.autoDownmixForTranscription)
        }
        set { setValue(newValue, forKey: Keys.autoDownmixForTranscription) }
    }
} 