import Foundation

enum TranscriptionLanguageSupport {
    private static let assemblyAIRealtimeLanguageCodes = ["en", "es", "de", "fr", "pt", "it"]

    private static let assemblyAIBatchLanguageCodes = [
        "en", "en_au", "en_uk", "en_us", "es", "fr", "de", "it", "pt", "nl",
        "hi", "ja", "zh", "fi", "ko", "pl", "ru", "tr", "uk", "vi", "af",
        "sq", "am", "ar", "hy", "as", "az", "ba", "eu", "be", "bn", "bs",
        "br", "bg", "my", "ca", "hr", "cs", "da", "et", "fo", "gl", "ka",
        "el", "gu", "ht", "ha", "haw", "he", "hu", "is", "id", "jw", "kn",
        "kk", "km", "lo", "la", "lv", "ln", "lt", "lb", "mk", "mg", "ms",
        "ml", "mt", "mi", "mr", "mn", "ne", "no", "nn", "oc", "pa", "ps",
        "fa", "ro", "sa", "sr", "sn", "sd", "si", "sk", "sl", "so", "su",
        "sw", "sv", "de_ch", "tl", "tg", "ta", "tt", "te", "th", "bo",
        "tk", "ur", "uz", "cy", "yi", "yo"
    ]

    static func languages(for model: any TranscriptionModel) -> [String: String] {
        if model.provider == .assemblyAI {
            return assemblyAILanguages(usesRealtime: assemblyAIUsesRealtime(for: model))
        }

        return model.supportedLanguages
    }

    static func validLanguageOrFallback(_ language: String?, for model: any TranscriptionModel) -> String {
        let languages = languages(for: model)

        if let language, languages[language] != nil {
            return language
        }

        if languages["auto"] != nil {
            return "auto"
        }

        if languages["en"] != nil {
            return "en"
        }

        return languages.keys.sorted { lhs, rhs in
            languages[lhs, default: lhs] < languages[rhs, default: rhs]
        }.first ?? "en"
    }

    private static func assemblyAILanguages(usesRealtime: Bool) -> [String: String] {
        let codes = usesRealtime ? assemblyAIRealtimeLanguageCodes : assemblyAIBatchLanguageCodes
        var filtered = LanguageDictionary.all.filter { codes.contains($0.key) }
        filtered["auto"] = "Auto-detect"
        return filtered
    }

    private static func assemblyAIUsesRealtime(for model: any TranscriptionModel) -> Bool {
        guard model.provider == .assemblyAI, model.supportsStreaming else {
            return false
        }

        if let cloudProvider = CloudProviderRegistry.provider(for: model.provider), cloudProvider.isStreamingOnly {
            return true
        }

        return UserDefaults.standard.object(forKey: "streaming-enabled-\(model.name)") as? Bool ?? true
    }
}

enum LanguageDictionary {
    static func forProvider(isMultilingual: Bool, provider: ModelProvider = .whisper) -> [String: String] {
        if !isMultilingual {
            return ["en": "English"]
        }

        if let cloudProvider = CloudProviderRegistry.provider(for: provider) {
            guard let codes = cloudProvider.languageCodes else {
                return all
            }
            var filtered = all.filter { codes.contains($0.key) }
            if cloudProvider.includesAutoDetect { filtered["auto"] = "Auto-detect" }
            return filtered
        }

        switch provider {
        case .nativeApple:
            let codes = ["ar", "de", "en", "es", "fr", "it", "ja", "ko", "pt", "yue", "zh"]
            return all.filter { codes.contains($0.key) }

        case .fluidAudio:
            let codes = [
                "bg", "cs", "da", "de", "el", "en", "es", "et", "fi", "fr",
                "hr", "hu", "it", "lt", "lv", "mt", "nl", "pl", "pt", "ro",
                "ru", "sk", "sl", "sv", "uk"
            ]
            var filtered = all.filter { codes.contains($0.key) }
            filtered["auto"] = "Auto-detect"
            return filtered

        default:
            return all
        }
    }

    // Apple Native Speech languages in BCP-47 format
    // Based on actual supported locales from SpeechTranscriber.supportedLocales
    static let appleNative: [String: String] = [
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
        "es-ES": "Spanish (Spain)",
        "es-MX": "Spanish (Mexico)",
        "es-US": "Spanish (United States)",
        "es-CO": "Spanish (Colombia)",
        "es-CL": "Spanish (Chile)",
        "es-419": "Spanish (Latin America)",
        "fr-FR": "French (France)",
        "fr-CA": "French (Canada)",
        "fr-BE": "French (Belgium)",
        "fr-CH": "French (Switzerland)",
        "de-DE": "German (Germany)",
        "de-AT": "German (Austria)",
        "de-CH": "German (Switzerland)",
        "zh-CN": "Chinese Simplified (China)",
        "zh-TW": "Chinese Traditional (Taiwan)",
        "zh-HK": "Chinese Traditional (Hong Kong)",
        "ja-JP": "Japanese (Japan)",
        "ko-KR": "Korean (South Korea)",
        "yue-CN": "Cantonese (China)",
        "pt-BR": "Portuguese (Brazil)",
        "pt-PT": "Portuguese (Portugal)",
        "it-IT": "Italian (Italy)",
        "it-CH": "Italian (Switzerland)",
        "ar-SA": "Arabic (Saudi Arabia)"
    ]

    static let all: [String: String] = [
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
        "de_ch": "Swiss German",
        "el": "Greek",
        "en": "English",
        "en_au": "Australian English",
        "en_uk": "British English",
        "en_us": "US English",
        "es": "Spanish",
        "et": "Estonian",
        "eu": "Basque",
        "fa": "Persian",
        "fi": "Finnish",
        "fil": "Filipino",
        "fo": "Faroese",
        "fr": "French",
        "ga": "Irish",
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
        "ig": "Igbo",
        "is": "Icelandic",
        "it": "Italian",
        "ja": "Japanese",
        "jw": "Javanese",
        "ka": "Georgian",
        "kk": "Kazakh",
        "km": "Khmer",
        "kn": "Kannada",
        "ko": "Korean",
        "ku": "Kurdish",
        "ky": "Kyrgyz",
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
        "or": "Odia",
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
        "wo": "Wolof",
        "xh": "Xhosa",
        "yi": "Yiddish",
        "yo": "Yoruba",
        "yue": "Cantonese",
        "zh": "Chinese",
        "zu": "Zulu"
    ]
}
