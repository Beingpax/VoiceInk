import Testing

@testable import VoiceInk

struct LanguageDictionaryTests {

    @Test func indianEnglishIsSupported() {
        // Core to why this fork exists — see CONTEXT.md.
        #expect(LanguageDictionary.all["en-IN"] == "English (India)")
        #expect(LanguageDictionary.appleNative["en-IN"] == "English (India)")
    }

    @Test func nonMultilingualProvidersAreEnglishOnly() {
        let languages = LanguageDictionary.forProvider(isMultilingual: false, provider: .whisper)
        #expect(languages == ["en": "English"])
    }

    @Test func whisperMultilingualIncludesAutoDetect() {
        let languages = LanguageDictionary.forProvider(isMultilingual: true, provider: .whisper)
        #expect(languages["auto"] != nil)
        #expect(languages["hi"] == "Hindi")
    }

    @Test func fluidAudioAlwaysIncludesAutoDetect() {
        let languages = LanguageDictionary.forProvider(isMultilingual: true, provider: .fluidAudio)
        #expect(languages["auto"] == "Auto-detect")
    }

    @Test func validLanguageOrFallbackReturnsRequestedLanguageWhenSupported() {
        let model = WhisperModel(
            name: "ggml-large-v3", displayName: "Large v3", size: "2.9 GB",
            supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .whisper),
            description: "", speed: 0.3, accuracy: 0.95, ramUsage: 3.9)

        #expect(TranscriptionLanguageSupport.validLanguageOrFallback("hi", for: model) == "hi")
    }

    @Test func validLanguageOrFallbackFallsBackToAutoWhenUnsupported() {
        let model = WhisperModel(
            name: "ggml-large-v3", displayName: "Large v3", size: "2.9 GB",
            supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .whisper),
            description: "", speed: 0.3, accuracy: 0.95, ramUsage: 3.9)

        #expect(TranscriptionLanguageSupport.validLanguageOrFallback("not-a-real-code", for: model) == "auto")
    }

    @Test func validLanguageOrFallbackFallsBackToEnglishWhenNoAutoDetect() {
        let model = WhisperModel(
            name: "ggml-tiny.en", displayName: "Tiny (English)", size: "75 MB",
            supportedLanguages: LanguageDictionary.forProvider(isMultilingual: false, provider: .whisper),
            description: "", speed: 0.95, accuracy: 0.65, ramUsage: 0.3)

        #expect(TranscriptionLanguageSupport.validLanguageOrFallback(nil, for: model) == "en")
    }
}
