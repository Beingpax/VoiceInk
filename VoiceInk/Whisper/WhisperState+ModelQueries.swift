import Foundation

extension WhisperState {
    var usableModels: [any TranscriptionModel] {
        allAvailableModels.filter { model in
            switch model.provider {
            case .local:
                return availableModels.contains { $0.name == model.name }
            case .parakeet:
                return isParakeetModelDownloaded(named: model.name)
            case .nativeApple:
                if #available(macOS 26, *) {
                    return true
                } else {
                    return false
                }
            case .groq:
                return KeychainManager.shared.exists(forKey: "groqAPIKey")
            case .elevenLabs:
                return KeychainManager.shared.exists(forKey: "elevenLabsAPIKey")
            case .deepgram:
                return KeychainManager.shared.exists(forKey: "deepgramAPIKey")
            case .mistral:
                return KeychainManager.shared.exists(forKey: "mistralAPIKey")
            case .gemini:
                return KeychainManager.shared.exists(forKey: "geminiAPIKey")
            case .soniox:
                return KeychainManager.shared.exists(forKey: "sonioxAPIKey")
            case .custom:
                // Custom models are always usable since they contain their own API keys
                return true
            }
        }
    }
} 
