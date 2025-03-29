import Foundation

struct PowerModeConfig: Codable, Identifiable, Equatable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    var appName: String
    var isAIEnhancementEnabled: Bool
    var selectedPrompt: String? // UUID string of the selected prompt
    var urlConfigs: [URLConfig]? // Optional URL configurations
    
    static func == (lhs: PowerModeConfig, rhs: PowerModeConfig) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier
    }
}

// Simple URL configuration
struct URLConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var url: String // Simple URL like "google.com"
    var promptId: String? // UUID string of the selected prompt for this URL
    
    init(url: String, promptId: String? = nil) {
        self.id = UUID()
        self.url = url
        self.promptId = promptId
    }
}

class PowerModeManager: ObservableObject {
    static let shared = PowerModeManager()
    @Published var configurations: [PowerModeConfig] = []
    @Published var defaultConfig: PowerModeConfig
    @Published var isPowerModeEnabled: Bool
    
    private let configKey = UserDefaultsKeys.PowerMode.config
    private let defaultConfigKey = UserDefaultsKeys.PowerMode.defaultConfig
    private let powerModeEnabledKey = UserDefaultsKeys.PowerMode.isEnabled
    
    private init() {
        // Load power mode enabled state
        self.isPowerModeEnabled = UserDefaults.standard.bool(forKey: powerModeEnabledKey)
        
        // Initialize default config with default values
        if let data = UserDefaults.standard.data(forKey: defaultConfigKey),
           let config = try? JSONDecoder().decode(PowerModeConfig.self, from: data) {
            defaultConfig = config
        } else {
            defaultConfig = PowerModeConfig(
                bundleIdentifier: "default",
                appName: "Default Configuration",
                isAIEnhancementEnabled: false,
                selectedPrompt: nil
            )
            saveDefaultConfig()
        }
        loadConfigurations()
    }
    
    private func loadConfigurations() {
        if let data = UserDefaults.standard.data(forKey: configKey),
           let configs = try? JSONDecoder().decode([PowerModeConfig].self, from: data) {
            configurations = configs
        }
    }
    
    func saveConfigurations() {
        if let data = try? JSONEncoder().encode(configurations) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
    }
    
    private func saveDefaultConfig() {
        if let data = try? JSONEncoder().encode(defaultConfig) {
            UserDefaults.standard.set(data, forKey: defaultConfigKey)
        }
    }
    
    func addConfiguration(_ config: PowerModeConfig) {
        if !configurations.contains(config) {
            configurations.append(config)
            saveConfigurations()
        }
    }
    
    func removeConfiguration(for bundleIdentifier: String) {
        configurations.removeAll { $0.bundleIdentifier == bundleIdentifier }
        saveConfigurations()
    }
    
    func getConfiguration(for bundleIdentifier: String) -> PowerModeConfig? {
        if bundleIdentifier == "default" {
            return defaultConfig
        }
        return configurations.first { $0.bundleIdentifier == bundleIdentifier }
    }
    
    func updateConfiguration(_ config: PowerModeConfig) {
        if config.bundleIdentifier == "default" {
            defaultConfig = config
            saveDefaultConfig()
        } else if let index = configurations.firstIndex(where: { $0.bundleIdentifier == config.bundleIdentifier }) {
            configurations[index] = config
            saveConfigurations()
        }
    }
    
    // Get configuration for a specific URL
    func getConfigurationForURL(_ url: String) -> (config: PowerModeConfig, urlConfig: URLConfig)? {
        let cleanedURL = url.lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
        
        for config in configurations {
            if let urlConfigs = config.urlConfigs {
                for urlConfig in urlConfigs {
                    let configURL = urlConfig.url.lowercased()
                        .replacingOccurrences(of: "https://", with: "")
                        .replacingOccurrences(of: "http://", with: "")
                        .replacingOccurrences(of: "www.", with: "")
                    
                    if cleanedURL.contains(configURL) {
                        return (config, urlConfig)
                    }
                }
            }
        }
        return nil
    }
    
    // Add URL configuration
    func addURLConfig(_ urlConfig: URLConfig, to config: PowerModeConfig) {
        if var updatedConfig = configurations.first(where: { $0.id == config.id }) {
            var configs = updatedConfig.urlConfigs ?? []
            configs.append(urlConfig)
            updatedConfig.urlConfigs = configs
            updateConfiguration(updatedConfig)
        }
    }
    
    // Remove URL configuration
    func removeURLConfig(_ urlConfig: URLConfig, from config: PowerModeConfig) {
        if var updatedConfig = configurations.first(where: { $0.id == config.id }) {
            updatedConfig.urlConfigs?.removeAll(where: { $0.id == urlConfig.id })
            updateConfiguration(updatedConfig)
        }
    }
    
    // Update URL configuration
    func updateURLConfig(_ urlConfig: URLConfig, in config: PowerModeConfig) {
        if var updatedConfig = configurations.first(where: { $0.id == config.id }) {
            if let index = updatedConfig.urlConfigs?.firstIndex(where: { $0.id == urlConfig.id }) {
                updatedConfig.urlConfigs?[index] = urlConfig
                updateConfiguration(updatedConfig)
            }
        }
    }
    
    // Save power mode enabled state
    func savePowerModeEnabled() {
        UserDefaults.standard.set(isPowerModeEnabled, forKey: powerModeEnabledKey)
    }
} 