import Foundation
import os

class CustomModelManager: ObservableObject {
    static let shared = CustomModelManager()
    
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "CustomModelManager")
    private let userDefaults = UserDefaults.standard
    private let customModelsKey = "customCloudModels"
    
    @Published var customModels: [CustomCloudModel] = []
    
    private init() {
        loadCustomModels()
    }
    
    // MARK: - CRUD Operations
    
    func addCustomModel(_ model: CustomCloudModel) {
        customModels.append(model)
        saveCustomModels()
        logger.info("Added custom model: \(model.displayName)")
    }
    
    func removeCustomModel(withId id: UUID) {
        // Delete API Key from Keychain
        try? KeychainManager.shared.delete(forKey: "CustomModel_\(id)_APIKey")
        
        customModels.removeAll { $0.id == id }
        saveCustomModels()
        logger.info("Removed custom model with ID: \(id)")
    }
    
    func updateCustomModel(_ updatedModel: CustomCloudModel) {
        if let index = customModels.firstIndex(where: { $0.id == updatedModel.id }) {
            customModels[index] = updatedModel
            saveCustomModels()
            logger.info("Updated custom model: \(updatedModel.displayName)")
        }
    }
    
    // MARK: - Persistence
    
    private func loadCustomModels() {
        // First, try to load from Keychain
        if let keychainString = KeychainManager.shared.retrieve(forKey: customModelsKey),
           let data = keychainString.data(using: .utf8) {
            do {
                customModels = try JSONDecoder().decode([CustomCloudModel].self, from: data)
                logger.info("Loaded custom models from Keychain")
                return
            } catch {
                logger.error("Failed to decode custom models from Keychain: \(error.localizedDescription)")
            }
        }

        // Fallback: Try to migrate from UserDefaults
        if let data = userDefaults.data(forKey: customModelsKey) {
            do {
                // Define legacy struct to capture the stored apiKey
                struct LegacyCustomCloudModel: Codable {
                    let id: UUID
                    let name: String
                    let displayName: String
                    let description: String
                    let apiEndpoint: String
                    let modelName: String
                    let apiKey: String // Stored property in old model
                    let isMultilingualModel: Bool
                    let supportedLanguages: [String: String]?
                }

                let legacyModels = try JSONDecoder().decode([LegacyCustomCloudModel].self, from: data)
                var migratedModels: [CustomCloudModel] = []
                
                for legacy in legacyModels {
                    // Save API Key to Keychain
                    try KeychainManager.shared.save(legacy.apiKey, forKey: "CustomModel_\(legacy.id)_APIKey")
                    
                    // Create new model using the current struct
                    let newModel = CustomCloudModel(
                        id: legacy.id,
                        name: legacy.name,
                        displayName: legacy.displayName,
                        description: legacy.description,
                        apiEndpoint: legacy.apiEndpoint,
                        modelName: legacy.modelName,
                        isMultilingual: legacy.isMultilingualModel,
                        supportedLanguages: legacy.supportedLanguages
                    )
                    migratedModels.append(newModel)
                }
                
                customModels = migratedModels
                logger.info("Migrated \(migratedModels.count) custom models from UserDefaults to Keychain")
                
                // Save to Keychain and remove from UserDefaults
                saveCustomModels()
                userDefaults.removeObject(forKey: customModelsKey)
            } catch {
                logger.error("Failed to decode custom models from UserDefaults: \(error.localizedDescription)")
                customModels = []
            }
        } else {
            logger.info("No custom models found")
        }
    }

    func saveCustomModels() {
        do {
            let data = try JSONEncoder().encode(customModels)
            if let jsonString = String(data: data, encoding: .utf8) {
                try KeychainManager.shared.save(jsonString, forKey: customModelsKey)
                logger.info("Saved custom models to Keychain")
            }
        } catch {
            logger.error("Failed to save custom models to Keychain: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Validation
    
    func validateModel(name: String, displayName: String, apiEndpoint: String, apiKey: String, modelName: String) -> [String] {
        var errors: [String] = []
        
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Name cannot be empty")
        }
        
        if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Display name cannot be empty")
        }
        
        if apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("API endpoint cannot be empty")
        } else if !isValidURL(apiEndpoint) {
            errors.append("API endpoint must be a valid URL")
        }
        
        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("API key cannot be empty")
        }
        
        if modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Model name cannot be empty")
        }
        
        // Check for duplicate names
        if customModels.contains(where: { $0.name == name }) {
            errors.append("A model with this name already exists")
        }
        
        return errors
    }
    
    func validateModel(name: String, displayName: String, apiEndpoint: String, apiKey: String, modelName: String, excludingId: UUID? = nil) -> [String] {
        var errors: [String] = []
        
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Name cannot be empty")
        }
        
        if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Display name cannot be empty")
        }
        
        if apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("API endpoint cannot be empty")
        } else if !isValidURL(apiEndpoint) {
            errors.append("API endpoint must be a valid URL")
        }
        
        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("API key cannot be empty")
        }
        
        if modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Model name cannot be empty")
        }
        
        // Check for duplicate names, excluding the specified ID
        if customModels.contains(where: { $0.name == name && $0.id != excludingId }) {
            errors.append("A model with this name already exists")
        }
        
        return errors
    }
    
    private func isValidURL(_ string: String) -> Bool {
        if let url = URL(string: string) {
            return url.scheme != nil && url.host != nil
        }
        return false
    }
} 
