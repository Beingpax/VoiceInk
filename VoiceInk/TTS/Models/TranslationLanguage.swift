import Foundation

struct TranslationLanguage: Identifiable, Equatable, Hashable {
    let code: String
    let displayName: String

    var id: String { code }
}

extension TranslationLanguage {
    static let english = TranslationLanguage(code: "en", displayName: "English")

    static let supported: [TranslationLanguage] = [
        .english,
        TranslationLanguage(code: "es", displayName: "Spanish"),
        TranslationLanguage(code: "fr", displayName: "French"),
        TranslationLanguage(code: "de", displayName: "German"),
        TranslationLanguage(code: "it", displayName: "Italian"),
        TranslationLanguage(code: "pt", displayName: "Portuguese"),
        TranslationLanguage(code: "ja", displayName: "Japanese"),
        TranslationLanguage(code: "ko", displayName: "Korean"),
        TranslationLanguage(code: "zh", displayName: "Chinese (Simplified)"),
        TranslationLanguage(code: "hi", displayName: "Hindi"),
        TranslationLanguage(code: "ar", displayName: "Arabic")
    ]
}
