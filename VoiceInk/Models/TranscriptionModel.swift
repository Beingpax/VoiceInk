import Foundation

// Enum to differentiate between model providers
enum ModelProvider: String, Codable, Hashable, CaseIterable {
    case local = "Local"
    case groq = "Groq"
    case elevenLabs = "ElevenLabs"
    case deepgram = "Deepgram"
    case custom = "Custom"
    case nativeApple = "Native Apple"
    case parakeetTDT = "Parakeet TDT"
    // Future providers can be added here
}

// A unified protocol for any transcription model
protocol TranscriptionModel: Identifiable, Hashable {
    var id: UUID { get }
    var name: String { get }
    var displayName: String { get }
    var description: String { get }
    var provider: ModelProvider { get }
    
    // Language capabilities
    var isMultilingualModel: Bool { get }
    var supportedLanguages: [String: String] { get }
}

extension TranscriptionModel {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    var language: String {
        isMultilingualModel ? "Multilingual" : "English-only"
    }
}

// A new struct for Apple's native models
struct NativeAppleModel: TranscriptionModel {
    let id = UUID()
    let name: String
    let displayName: String
    let description: String
    let provider: ModelProvider = .nativeApple
    let isMultilingualModel: Bool
    let supportedLanguages: [String: String]
}

// A new struct for cloud models
struct CloudModel: TranscriptionModel {
    let id: UUID
    let name: String
    let displayName: String
    let description: String
    let provider: ModelProvider
    let speed: Double
    let accuracy: Double
    let isMultilingualModel: Bool
    let supportedLanguages: [String: String]

    init(id: UUID = UUID(), name: String, displayName: String, description: String, provider: ModelProvider, speed: Double, accuracy: Double, isMultilingual: Bool, supportedLanguages: [String: String]) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.description = description
        self.provider = provider
        self.speed = speed
        self.accuracy = accuracy
        self.isMultilingualModel = isMultilingual
        self.supportedLanguages = supportedLanguages
    }
}

// A new struct for custom cloud models
struct CustomCloudModel: TranscriptionModel, Codable {
    let id: UUID
    let name: String
    let displayName: String
    let description: String
    let provider: ModelProvider = .custom
    let apiEndpoint: String
    let apiKey: String
    let modelName: String
    let isMultilingualModel: Bool
    let supportedLanguages: [String: String]

    init(id: UUID = UUID(), name: String, displayName: String, description: String, apiEndpoint: String, apiKey: String, modelName: String, isMultilingual: Bool = true, supportedLanguages: [String: String]? = nil) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.description = description
        self.apiEndpoint = apiEndpoint
        self.apiKey = apiKey
        self.modelName = modelName
        self.isMultilingualModel = isMultilingual
        self.supportedLanguages = supportedLanguages ?? PredefinedModels.getLanguageDictionary(isMultilingual: isMultilingual)
    }
}

// A new struct for Parakeet TDT models
struct ParakeetTDTModel: TranscriptionModel {
    let id = UUID()
    let name: String
    let displayName: String
    let description: String
    let provider: ModelProvider = .parakeetTDT
    let isMultilingualModel: Bool
    let supportedLanguages: [String: String]
    let size: String
    let speed: Double
    let accuracy: Double
    let ramUsage: Double
    let isInstalled: Bool
    
    init(name: String, displayName: String, description: String, isMultilingual: Bool = false, supportedLanguages: [String: String]? = nil, size: String, speed: Double, accuracy: Double, ramUsage: Double, isInstalled: Bool = false) {
        self.name = name
        self.displayName = displayName
        self.description = description
        self.isMultilingualModel = isMultilingual
        self.supportedLanguages = supportedLanguages ?? (isMultilingual ? PredefinedModels.allLanguages : ["en": "English"])
        self.size = size
        self.speed = speed
        self.accuracy = accuracy
        self.ramUsage = ramUsage
        self.isInstalled = isInstalled
    }
} 