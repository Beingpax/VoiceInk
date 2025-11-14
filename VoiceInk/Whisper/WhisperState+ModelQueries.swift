import Foundation

extension WhisperState {
    var usableModels: [any TranscriptionModel] {
        let keychain = KeychainManager()
        return allAvailableModels.filter { model in
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
                return keychain.hasAPIKey(for: "GROQ")
            case .elevenLabs:
                return keychain.hasAPIKey(for: "ElevenLabs")
            case .deepgram:
                return keychain.hasAPIKey(for: "Deepgram")
            case .mistral:
                return keychain.hasAPIKey(for: "Mistral")
            case .gemini:
                return keychain.hasAPIKey(for: "Gemini")
            case .soniox:
                return keychain.hasAPIKey(for: "Soniox")
            case .custom:
                // Custom models are always usable since they contain their own API keys
                return true
            }
        }
    }
} 
