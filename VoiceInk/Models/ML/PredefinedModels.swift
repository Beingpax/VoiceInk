import Foundation
 
 enum PredefinedModels {
    static func getLanguageDictionary(isMultilingual: Bool, provider: ModelProvider = .local) -> [String: String] {
        if !isMultilingual {
            return ["en": "English"]
        } else {
            // For Apple Native models, return only supported languages in simple format
            if provider == .nativeApple {
                let appleSupportedCodes = ["ar", "de", "en", "es", "fr", "it", "ja", "ko", "pt", "yue", "zh"]
                return allLanguages.filter { appleSupportedCodes.contains($0.key) }
            }
            // For Soniox, return only the 60 languages supported by stt-async-v4
            if provider == .soniox {
                let sonioxSupportedCodes = [
                    "af", "sq", "ar", "az", "eu", "be", "bn", "bs", "bg", "ca",
                    "zh", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "gl",
                    "de", "el", "gu", "he", "hi", "hu", "id", "it", "ja", "kn",
                    "kk", "ko", "lv", "lt", "mk", "ms", "ml", "mr", "no", "fa",
                    "pl", "pt", "pa", "ro", "ru", "sr", "sk", "sl", "es", "sw",
                    "sv", "tl", "ta", "te", "th", "tr", "uk", "ur", "vi", "cy"
                ]
                var filtered = allLanguages.filter { sonioxSupportedCodes.contains($0.key) }
                filtered["auto"] = "Auto-detect"
                return filtered
            }
            return allLanguages
        }
    }
    
    // Apple Native Speech specific languages with proper BCP-47 format
    // Based on actual supported locales from SpeechTranscriber.supportedLocales
    static let appleNativeLanguages = [
        // English variants
        "en-US": "English (United States)",
        "en-GB": "English (United Kingdom)",
        "en-CA": "English (Canada)",
        "en-AU": "English (Australia)",
        "en-IN": "English (India)",
        "en-IE": "English (Ireland)",
        "en-NZ": "English (New Zealand)",
        "en-ZA": "English (South Africa)",
        "en-SA": "English (Saudi Arabia)",
        "en-AE": "English (UAE)",
        "en-SG": "English (Singapore)",
        "en-PH": "English (Philippines)",
        "en-ID": "English (Indonesia)",
        
        // Spanish variants
        "es-ES": "Spanish (Spain)",
        "es-MX": "Spanish (Mexico)",
        "es-US": "Spanish (United States)",
        "es-CO": "Spanish (Colombia)",
        "es-CL": "Spanish (Chile)",
        "es-419": "Spanish (Latin America)",
        
        // French variants
        "fr-FR": "French (France)",
        "fr-CA": "French (Canada)",
        "fr-BE": "French (Belgium)",
        "fr-CH": "French (Switzerland)",
        
        // German variants
        "de-DE": "German (Germany)",
        "de-AT": "German (Austria)",
        "de-CH": "German (Switzerland)",
        
        // Chinese variants
        "zh-CN": "Chinese Simplified (China)",
        "zh-TW": "Chinese Traditional (Taiwan)",
        "zh-HK": "Chinese Traditional (Hong Kong)",
        
        // Other Asian languages
        "ja-JP": "Japanese (Japan)",
        "ko-KR": "Korean (South Korea)",
        "yue-CN": "Cantonese (China)",
        
        // Portuguese variants
        "pt-BR": "Portuguese (Brazil)",
        "pt-PT": "Portuguese (Portugal)",
        
        // Italian variants
        "it-IT": "Italian (Italy)",
        "it-CH": "Italian (Switzerland)",
        
        // Arabic
        "ar-SA": "Arabic (Saudi Arabia)"
    ]
    
    static var models: [any TranscriptionModel] {
        return predefinedModels + CustomModelManager.shared.customModels
    }
    
    private static let predefinedModels: [any TranscriptionModel] = [
        // Native Apple Model
        NativeAppleModel(
            name: "apple-speech",
            displayName: "Apple Speech",
            description: "Uses the native Apple Speech framework for transcription. Requires macOS 26",
            isMultilingualModel: true,
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .nativeApple)
        ),
        
        // Parakeet Models
        ParakeetModel(
            name: "parakeet-tdt-0.6b-v2",
            displayName: "Parakeet V2",
            description: "NVIDIA's Parakeet V2 model optimized for lightning-fast English-only transcription",
            size: "474 MB",
            speed: 0.99,
            accuracy: 0.94,
            ramUsage: 0.8,
            supportedLanguages: getLanguageDictionary(isMultilingual: false, provider: .parakeet)
        ),
        ParakeetModel(
            name: "parakeet-tdt-0.6b-v3",
            displayName: "Parakeet V3",
            description: "NVIDIA's Parakeet V3 model with multilingual support across English and 25 European languages",
            size: "494 MB",
            speed: 0.99,
            accuracy: 0.94,
            ramUsage: 0.8,
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .parakeet)
        ),
        
         // Local Models
         LocalModel(
             name: "ggml-tiny",
             displayName: "Tiny",
             size: "75 MB",
             supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .local),
             description: "Tiny model, fastest, least accurate",
             speed: 0.95,
             accuracy: 0.6,
             ramUsage: 0.3
         ),
         LocalModel(
             name: "ggml-tiny.en",
             displayName: "Tiny (English)",
             size: "75 MB",
             supportedLanguages: getLanguageDictionary(isMultilingual: false, provider: .local),
             description: "Tiny model optimized for English, fastest, least accurate",
             speed: 0.95,
             accuracy: 0.65,
             ramUsage: 0.3
         ),
         LocalModel(
             name: "ggml-base",
             displayName: "Base",
             size: "142 MB",
             supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .local),
             description: "Base model, good balance between speed and accuracy, supports multiple languages",
             speed: 0.85,
             accuracy: 0.72,
             ramUsage: 0.5
         ),
         LocalModel(
             name: "ggml-base.en",
             displayName: "Base (English)",
             size: "142 MB",
             supportedLanguages: getLanguageDictionary(isMultilingual: false, provider: .local),
             description: "Base model optimized for English, good balance between speed and accuracy",
             speed: 0.85,
             accuracy: 0.75,
             ramUsage: 0.5
         ),
         LocalModel(
             name: "ggml-large-v2",
             displayName: "Large v2",
             size: "2.9 GB",
             supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .local),
             description: "Large model v2, slower than Medium but more accurate",
             speed: 0.3,
             accuracy: 0.96,
             ramUsage: 3.8
         ),
         LocalModel(
             name: "ggml-large-v3",
             displayName: "Large v3",
             size: "2.9 GB",
             supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .local),
             description: "Large model v3, very slow but most accurate",
             speed: 0.3,
             accuracy: 0.98,
             ramUsage: 3.9
         ),
         LocalModel(
             name: "ggml-large-v3-turbo",
             displayName: "Large v3 Turbo",
             size: "1.5 GB",
             supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .local),
             description:
             "Large model v3 Turbo, faster than v3 with similar accuracy",
             speed: 0.75,
             accuracy: 0.97,
             ramUsage: 1.8
         ),
         LocalModel(
             name: "ggml-large-v3-turbo-q5_0",
             displayName: "Large v3 Turbo (Quantized)",
             size: "547 MB",
             supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .local),
             description: "Quantized version of Large v3 Turbo, faster with slightly lower accuracy",
             speed: 0.75,
             accuracy: 0.95,
             ramUsage: 1.0
         ),
         
                 // Cloud Models
        CloudModel(
            name: "whisper-large-v3-turbo",
            displayName: "Whisper Large v3 Turbo (Groq)",
            description: "Whisper Large v3 Turbo model with Groq's lightning-speed inference",
            provider: .groq,
            speed: 0.65,
            accuracy: 0.95,
            isMultilingual: true,
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .groq)
        ),
        CloudModel(
           name: "scribe_v1",
           displayName: "Scribe v1 (ElevenLabs)",
           description: "ElevenLabs' Scribe model for fast & accurate transcription",
           provider: .elevenLabs,
           speed: 0.7,
           accuracy: 0.98,
           isMultilingual: true,
           supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .elevenLabs)
       ),
       CloudModel(
           name: "scribe_v2",
           displayName: "Scribe V2 Realtime (ElevenLabs)",
           description: "ElevenLabs' Scribe V2 Realtime model for the most accurate transcription",
           provider: .elevenLabs,
           speed: 0.99,
           accuracy: 0.98,
           isMultilingual: true,
           supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .elevenLabs)
       ),
       CloudModel(
           name: "nova-3",
           displayName: "Nova 3 Realtime (Deepgram)",
           description: "Deepgram's latest Nova 3 model for realtime transcription",
           provider: .deepgram,
           speed: 0.99,
           accuracy: 0.96,
           isMultilingual: true,
           supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .deepgram)
       ),
       CloudModel(
           name: "nova-3-medical",
           displayName: "Nova 3 Medical Realtime (Deepgram)",
           description: "Specialized medical transcription model optimized for clinical environments",
           provider: .deepgram,
           speed: 0.99,
           accuracy: 0.96,
           isMultilingual: false,
           supportedLanguages: getLanguageDictionary(isMultilingual: false, provider: .deepgram)
       ),
        CloudModel(
            name: "voxtral-mini-latest",
            displayName: "Voxtral Transcribe 2 (Mistral)",
            description: "Mistral's latest transcription model for fast and accurate transcription",
            provider: .mistral,
            speed: 0.8,
            accuracy: 0.98,
            isMultilingual: true,
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .mistral)
        ),
        CloudModel(
            name: "voxtral-mini-transcribe-realtime-2602",
            displayName: "Voxtral Realtime (Mistral)",
            description: "Mistral's Voxtral Realtime model for streaming transcription",
            provider: .mistral,
            speed: 0.99,
            accuracy: 0.97,
            isMultilingual: true,
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .mistral)
        ),
        
        // Gemini Models
        CloudModel(
            name: "gemini-2.5-pro",
            displayName: "Gemini 2.5 Pro",
            description: "Google's advanced model with high-quality transcription capabilities",
            provider: .gemini,
            speed: 0.7,
            accuracy: 0.97,
            isMultilingual: true,
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .gemini)
        ),
        CloudModel(
            name: "gemini-2.5-flash",
            displayName: "Gemini 2.5 Flash",
            description: "Google's optimized model for low-latency transcription",
            provider: .gemini,
            speed: 0.9,
            accuracy: 0.95,
            isMultilingual: true,
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .gemini)
        ),
        CloudModel(
            name: "gemini-3-pro-preview",
            displayName: "Gemini 3 Pro",
            description: "Google's latest model with enhanced transcription capabilities",
            provider: .gemini,
            speed: 0.75,
            accuracy: 0.97,
            isMultilingual: true,
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .gemini)
        ),
        CloudModel(
            name: "gemini-3-flash-preview",
            displayName: "Gemini 3 Flash",
            description: "Google's newest fast model combining intelligence with superior speed",
            provider: .gemini,
            speed: 0.92,
            accuracy: 0.95,
            isMultilingual: true,
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .gemini)
        )
        ,
        CloudModel(
            name: "stt-async-v4",
            displayName: "Soniox V4",
            description: "Soniox asynchronous transcription model v4 with human-parity accuracy",
            provider: .soniox,
            speed: 0.8,
            accuracy: 0.98,
            isMultilingual: true,
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .soniox)
        ),
        CloudModel(
            name: "stt-rt-v4",
            displayName: "Soniox Realtime V4",
            description: "Soniox real-time streaming model v4 for low-latency transcription",
            provider: .soniox,
            speed: 0.99,
            accuracy: 0.97,
            isMultilingual: true,
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .soniox)
        )
     ]
 
     static let allLanguages = [
         "auto": "Auto-detect",
         "af": "Afrikaans",
         "am": "Amharic",
         "ar": "Arabic",
         "as": "Assamese",
         "az": "Azerbaijani",
         "ba": "Bashkir",
         "be": "Belarusian",
         "bg": "Bulgarian",
         "bn": "Bengali",
         "bo": "Tibetan",
         "br": "Breton",
         "bs": "Bosnian",
         "ca": "Catalan",
         "cs": "Czech",
         "cy": "Welsh",
         "da": "Danish",
         "de": "German",
         "el": "Greek",
         "en": "English",
         "es": "Spanish",
         "et": "Estonian",
         "eu": "Basque",
         "fa": "Persian",
         "fi": "Finnish",
         "fo": "Faroese",
         "fr": "French",
         "gl": "Galician",
         "gu": "Gujarati",
         "ha": "Hausa",
         "haw": "Hawaiian",
         "he": "Hebrew",
         "hi": "Hindi",
         "hr": "Croatian",
         "ht": "Haitian Creole",
         "hu": "Hungarian",
         "hy": "Armenian",
         "id": "Indonesian",
         "is": "Icelandic",
         "it": "Italian",
         "ja": "Japanese",
         "jw": "Javanese",
         "ka": "Georgian",
         "kk": "Kazakh",
         "km": "Khmer",
         "kn": "Kannada",
         "ko": "Korean",
         "la": "Latin",
         "lb": "Luxembourgish",
         "ln": "Lingala",
         "lo": "Lao",
         "lt": "Lithuanian",
         "lv": "Latvian",
         "mg": "Malagasy",
         "mi": "Maori",
         "mk": "Macedonian",
         "ml": "Malayalam",
         "mn": "Mongolian",
         "mr": "Marathi",
         "ms": "Malay",
         "mt": "Maltese",
         "my": "Myanmar",
         "ne": "Nepali",
         "nl": "Dutch",
         "nn": "Norwegian Nynorsk",
         "no": "Norwegian",
         "oc": "Occitan",
         "pa": "Punjabi",
         "pl": "Polish",
         "ps": "Pashto",
         "pt": "Portuguese",
         "ro": "Romanian",
         "ru": "Russian",
         "sa": "Sanskrit",
         "sd": "Sindhi",
         "si": "Sinhala",
         "sk": "Slovak",
         "sl": "Slovenian",
         "sn": "Shona",
         "so": "Somali",
         "sq": "Albanian",
         "sr": "Serbian",
         "su": "Sundanese",
         "sv": "Swedish",
         "sw": "Swahili",
         "ta": "Tamil",
         "te": "Telugu",
         "tg": "Tajik",
         "th": "Thai",
         "tk": "Turkmen",
         "tl": "Tagalog",
         "tr": "Turkish",
         "tt": "Tatar",
         "uk": "Ukrainian",
         "ur": "Urdu",
         "uz": "Uzbek",
         "vi": "Vietnamese",
         "yi": "Yiddish",
         "yo": "Yoruba",
         "yue": "Cantonese",
         "zh": "Chinese",
     ]
 }
