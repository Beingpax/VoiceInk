import Foundation

enum TranscriptionModelRegistry {

    static var models: [any TranscriptionModel] {
        return predefinedModels + CustomCloudModelManager.shared.customModels
    }
    
    private static let predefinedModels: [any TranscriptionModel] = {
        let nonCloudModels: [any TranscriptionModel] = [
            // Native Apple Model
            NativeAppleModel(
                name: "apple-speech",
                displayName: "Apple Speech",
                description: "Uses the native Apple Speech framework for transcription. Requires macOS 26",
                isMultilingualModel: true,
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .nativeApple)
            ),

            // Parakeet Models
            FluidAudioModel(
                name: "parakeet-tdt-0.6b-v2",
                displayName: "Parakeet V2",
                description: "NVIDIA's Parakeet V2 model optimized for lightning-fast English-only transcription",
                size: "474 MB",
                speed: 0.99,
                accuracy: 0.94,
                ramUsage: 0.8,
                supportsStreaming: true,
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: false, provider: .fluidAudio)
            ),
            FluidAudioModel(
                name: "parakeet-tdt-0.6b-v3",
                displayName: "Parakeet V3",
                description: "Parakeet V3 with English and 25 European language support",
                size: "494 MB",
                speed: 0.99,
                accuracy: 0.94,
                ramUsage: 0.8,
                supportsStreaming: true,
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .fluidAudio)
            ),

            // Local Models
            WhisperModel(
                name: "ggml-tiny",
                displayName: "Tiny",
                size: "75 MB",
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .whisper),
                description: "Tiny model, fastest, least accurate",
                speed: 0.95,
                accuracy: 0.6,
                ramUsage: 0.3
            ),
            WhisperModel(
                name: "ggml-tiny.en",
                displayName: "Tiny (English)",
                size: "75 MB",
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: false, provider: .whisper),
                description: "Tiny model optimized for English, fastest, least accurate",
                speed: 0.95,
                accuracy: 0.65,
                ramUsage: 0.3
            ),
            WhisperModel(
                name: "ggml-base",
                displayName: "Base",
                size: "142 MB",
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .whisper),
                description: "Base model, good balance between speed and accuracy, supports multiple languages",
                speed: 0.85,
                accuracy: 0.72,
                ramUsage: 0.5
            ),
            WhisperModel(
                name: "ggml-base.en",
                displayName: "Base (English)",
                size: "142 MB",
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: false, provider: .whisper),
                description: "Base model optimized for English, good balance between speed and accuracy",
                speed: 0.85,
                accuracy: 0.75,
                ramUsage: 0.5
            ),
            WhisperModel(
                name: "ggml-large-v2",
                displayName: "Large v2",
                size: "2.9 GB",
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .whisper),
                description: "Large model v2, slower than Medium but more accurate",
                speed: 0.3,
                accuracy: 0.96,
                ramUsage: 3.8
            ),
            WhisperModel(
                name: "ggml-large-v3",
                displayName: "Large v3",
                size: "2.9 GB",
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .whisper),
                description: "Large model v3, very slow but most accurate",
                speed: 0.3,
                accuracy: 0.98,
                ramUsage: 3.9
            ),
            WhisperModel(
                name: "ggml-large-v3-turbo",
                displayName: "Large v3 Turbo",
                size: "1.5 GB",
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .whisper),
                description: "Large model v3 Turbo, faster than v3 with similar accuracy",
                speed: 0.75,
                accuracy: 0.97,
                ramUsage: 1.8
            ),
            WhisperModel(
                name: "ggml-large-v3-turbo-q5_0",
                displayName: "Large v3 Turbo (Quantized)",
                size: "547 MB",
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .whisper),
                description: "Quantized version of Large v3 Turbo, faster with slightly lower accuracy",
                speed: 0.75,
                accuracy: 0.95,
                ramUsage: 1.0
            )
        ]

        let cloudModels: [any TranscriptionModel] = CloudProviderRegistry.allProviders.flatMap { $0.models }
        return nonCloudModels + cloudModels
    }()
}
