import Foundation

@MainActor
protocol TextTranslationService {
    func translate(text: String, targetLanguageCode: String) async throws -> TranslationResult
    func hasCredentials() -> Bool
}
