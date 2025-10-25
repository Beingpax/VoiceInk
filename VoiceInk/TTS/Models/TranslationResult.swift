import Foundation

struct TranslationResult: Equatable {
    let originalText: String
    let translatedText: String
    let detectedLanguageCode: String
    let targetLanguageCode: String

    var detectedLanguageDisplayName: String {
        Locale.current.localizedString(forLanguageCode: detectedLanguageCode) ?? detectedLanguageCode.uppercased()
    }

    var targetLanguageDisplayName: String {
        Locale.current.localizedString(forLanguageCode: targetLanguageCode) ?? targetLanguageCode.uppercased()
    }
}
