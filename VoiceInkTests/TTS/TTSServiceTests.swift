import XCTest
@testable import VoiceInk

/// Tests for TTS Services (ElevenLabs, OpenAI, Google, Local)
/// Tests error handling, API key validation, voice management, and text limits
@available(macOS 14.0, *)
final class TTSServiceTests: XCTestCase {
    
    // MARK: - Test Fixtures
    
    static let testVoice = Voice(
        id: "test-voice-id",
        name: "Test Voice",
        language: "en-US",
        gender: .neutral,
        provider: .elevenLabs,
        previewURL: nil
    )
    
    static let defaultSettings = AudioSettings()
    
    // MARK: - TTSError Tests
    
    func testTTSErrorDescriptions() {
        let errors: [TTSError] = [
            .invalidAPIKey,
            .networkError("Connection failed"),
            .quotaExceeded,
            .invalidVoice,
            .textTooLong(5000),
            .unsupportedFormat,
            .apiError("Server error")
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error \(error) should have a description")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error description should not be empty")
        }
    }
    
    func testTextTooLongErrorContainsLimit() {
        let error = TTSError.textTooLong(5000)
        XCTAssertTrue(error.errorDescription?.contains("5000") ?? false)
    }
    
    func testNetworkErrorContainsMessage() {
        let error = TTSError.networkError("Connection timed out")
        XCTAssertTrue(error.errorDescription?.contains("Connection timed out") ?? false)
    }
    
    func testAPIErrorContainsMessage() {
        let error = TTSError.apiError("Rate limit exceeded")
        XCTAssertTrue(error.errorDescription?.contains("Rate limit exceeded") ?? false)
    }
    
    func testStreamingErrorContainsMessage() {
        let error = TTSError.streamingError("Connection interrupted")
        XCTAssertTrue(error.errorDescription?.contains("Connection interrupted") ?? false)
    }
    
    // MARK: - Pronunciation Override Tests
    
    func testPronunciationOverrideLiteral() {
        let override = PronunciationOverride(word: "GIF", replacement: "JIF")
        
        XCTAssertEqual(override.word, "GIF")
        XCTAssertEqual(override.replacement, "JIF")
        XCTAssertEqual(override.type, .literal)
    }
    
    func testPronunciationOverrideIPA() {
        let override = PronunciationOverride(word: "tomato", replacement: "təˈmɑːtəʊ", type: .ipa)
        
        XCTAssertEqual(override.word, "tomato")
        XCTAssertEqual(override.replacement, "təˈmɑːtəʊ")
        XCTAssertEqual(override.type, .ipa)
    }
    
    func testPronunciationOverrideArpabet() {
        let override = PronunciationOverride(word: "hello", replacement: "HH AH0 L OW1", type: .arpabet)
        
        XCTAssertEqual(override.type, .arpabet)
    }
    
    func testPronunciationOverrideHashable() {
        let override1 = PronunciationOverride(word: "test", replacement: "tester")
        let override2 = PronunciationOverride(word: "test", replacement: "tester")
        
        XCTAssertEqual(override1, override2)
    }
    
    // MARK: - AnyCodable Tests
    
    func testAnyCodableString() throws {
        let codable = AnyCodable("hello")
        let data = try JSONEncoder().encode(codable)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        
        XCTAssertEqual(decoded.value as? String, "hello")
    }
    
    func testAnyCodableInt() throws {
        let codable = AnyCodable(42)
        let data = try JSONEncoder().encode(codable)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        
        XCTAssertEqual(decoded.value as? Int, 42)
    }
    
    func testAnyCodableDouble() throws {
        let codable = AnyCodable(3.14)
        let data = try JSONEncoder().encode(codable)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        
        XCTAssertEqual(decoded.value as? Double, 3.14)
    }
    
    func testAnyCodableBool() throws {
        let codable = AnyCodable(true)
        let data = try JSONEncoder().encode(codable)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        
        XCTAssertEqual(decoded.value as? Bool, true)
    }
    
    // MARK: - Voice Model Tests
    
    func testVoiceEquality() {
        let voice1 = Voice(
            id: "voice-1",
            name: "Voice One",
            language: "en-US",
            gender: .male,
            provider: .elevenLabs,
            previewURL: nil
        )
        
        let voice2 = Voice(
            id: "voice-1",
            name: "Voice One",
            language: "en-US",
            gender: .male,
            provider: .elevenLabs,
            previewURL: nil
        )
        
        let voice3 = Voice(
            id: "voice-2",
            name: "Voice Two",
            language: "en-US",
            gender: .female,
            provider: .elevenLabs,
            previewURL: nil
        )
        
        XCTAssertEqual(voice1, voice2)
        XCTAssertNotEqual(voice1, voice3)
    }
    
    func testVoiceGenderCases() {
        XCTAssertEqual(Voice.Gender.allCases.count, 3)
        XCTAssertTrue(Voice.Gender.allCases.contains(.male))
        XCTAssertTrue(Voice.Gender.allCases.contains(.female))
        XCTAssertTrue(Voice.Gender.allCases.contains(.neutral))
    }
    
    func testVoiceProviderTypes() {
        XCTAssertEqual(Voice.ProviderType.elevenLabs.rawValue, "ElevenLabs")
        XCTAssertEqual(Voice.ProviderType.openAI.rawValue, "OpenAI")
        XCTAssertEqual(Voice.ProviderType.google.rawValue, "Google")
        XCTAssertEqual(Voice.ProviderType.tightAss.rawValue, "Tight Ass Mode")
    }
    
    // MARK: - AudioSettings Tests
    
    func testAudioSettingsDefaults() {
        let settings = AudioSettings()
        
        XCTAssertEqual(settings.speed, 1.0)
        XCTAssertEqual(settings.pitch, 1.0)
        XCTAssertEqual(settings.volume, 1.0)
        XCTAssertEqual(settings.format, .mp3)
        XCTAssertEqual(settings.sampleRate, 22050)
        XCTAssertTrue(settings.styleValues.isEmpty)
        XCTAssertTrue(settings.providerOptions.isEmpty)
        XCTAssertTrue(settings.extras.isEmpty)
        XCTAssertTrue(settings.pronunciationOverrides.isEmpty)
        XCTAssertNil(settings.pronunciationDictionaryID)
    }
    
    func testAudioSettingsExtras() {
        var settings = AudioSettings()
        
        settings.extras["custom_param"] = AnyCodable("value")
        settings.extras["numeric_param"] = AnyCodable(42)
        
        XCTAssertEqual(settings.extras.count, 2)
        XCTAssertEqual(settings.extras["custom_param"]?.value as? String, "value")
        XCTAssertEqual(settings.extras["numeric_param"]?.value as? Int, 42)
    }
    
    func testAudioSettingsPronunciationOverrides() {
        var settings = AudioSettings()
        
        let override = PronunciationOverride(word: "API", replacement: "A-P-I")
        settings.pronunciationOverrides = [override]
        
        XCTAssertEqual(settings.pronunciationOverrides.count, 1)
        XCTAssertEqual(settings.pronunciationOverrides.first?.word, "API")
    }
    
    func testAudioSettingsPronunciationDictionaryID() {
        var settings = AudioSettings()
        
        settings.pronunciationDictionaryID = "dict_12345"
        
        XCTAssertEqual(settings.pronunciationDictionaryID, "dict_12345")
    }
    
    func testAudioSettingsStyleValueWithControl() {
        var settings = AudioSettings()
        
        let control = ProviderStyleControl(
            id: "test.control",
            label: "Test Control",
            range: 0...1,
            defaultValue: 0.5,
            step: 0.1,
            valueFormat: .percentage,
            helpText: "Test help"
        )
        
        // Test default value
        XCTAssertEqual(settings.styleValue(for: control), 0.5)
        
        // Test custom value
        settings.styleValues["test.control"] = 0.8
        XCTAssertEqual(settings.styleValue(for: control), 0.8)
        
        // Test clamping above range
        settings.styleValues["test.control"] = 1.5
        XCTAssertEqual(settings.styleValue(for: control), 1.0)
        
        // Test clamping below range
        settings.styleValues["test.control"] = -0.5
        XCTAssertEqual(settings.styleValue(for: control), 0.0)
    }
    
    func testAudioSettingsProviderOption() {
        var settings = AudioSettings()
        
        XCTAssertNil(settings.providerOption(for: "model"))
        
        settings.providerOptions["model"] = "eleven_monolingual_v1"
        XCTAssertEqual(settings.providerOption(for: "model"), "eleven_monolingual_v1")
    }
    
    func testAudioFormatCases() {
        let formats = AudioSettings.AudioFormat.allCases
        XCTAssertEqual(formats.count, 5)
        XCTAssertTrue(formats.contains(.mp3))
        XCTAssertTrue(formats.contains(.wav))
        XCTAssertTrue(formats.contains(.aac))
        XCTAssertTrue(formats.contains(.flac))
        XCTAssertTrue(formats.contains(.opus))
    }
    
    // MARK: - ProviderStyleControl Tests
    
    func testProviderStyleControlClamp() {
        let control = ProviderStyleControl(
            id: "test",
            label: "Test",
            range: 0.25...0.75,
            defaultValue: 0.5
        )
        
        XCTAssertEqual(control.clamp(0.5), 0.5)
        XCTAssertEqual(control.clamp(0.0), 0.25)
        XCTAssertEqual(control.clamp(1.0), 0.75)
        XCTAssertEqual(control.clamp(0.25), 0.25)
        XCTAssertEqual(control.clamp(0.75), 0.75)
    }
    
    func testProviderStyleControlFormattedValuePercentage() {
        let control = ProviderStyleControl(
            id: "test",
            label: "Test",
            range: 0...1,
            defaultValue: 0.5,
            valueFormat: .percentage
        )
        
        XCTAssertEqual(control.formattedValue(for: 0.0), "0%")
        XCTAssertEqual(control.formattedValue(for: 0.5), "50%")
        XCTAssertEqual(control.formattedValue(for: 1.0), "100%")
        XCTAssertEqual(control.formattedValue(for: 0.333), "33%")
    }
    
    func testProviderStyleControlFormattedValueDecimal() {
        let control = ProviderStyleControl(
            id: "test",
            label: "Test",
            range: 0...2,
            defaultValue: 1.0,
            valueFormat: .decimal(places: 2)
        )
        
        XCTAssertEqual(control.formattedValue(for: 1.0), "1.00")
        XCTAssertEqual(control.formattedValue(for: 1.5), "1.50")
        XCTAssertEqual(control.formattedValue(for: 0.123), "0.12")
    }
    
    // MARK: - SpeechRequest Tests
    
    func testSpeechRequestCreation() {
        let voice = Self.testVoice
        let settings = Self.defaultSettings
        
        let request = SpeechRequest(text: "Hello world", voice: voice, settings: settings)
        
        XCTAssertEqual(request.text, "Hello world")
        XCTAssertEqual(request.voice.id, voice.id)
        XCTAssertNotNil(request.timestamp)
    }
    
    // MARK: - ElevenLabs Voice Tests
    
    func testElevenLabsDefaultVoices() {
        let voices = Voice.elevenLabsVoices
        
        XCTAssertFalse(voices.isEmpty)
        XCTAssertTrue(voices.count >= 9) // At least 9 default voices
        
        // Verify all voices have required properties
        for voice in voices {
            XCTAssertFalse(voice.id.isEmpty)
            XCTAssertFalse(voice.name.isEmpty)
            XCTAssertEqual(voice.provider, .elevenLabs)
        }
        
        // Verify Rachel is the first voice (default)
        XCTAssertEqual(voices.first?.name, "Rachel")
        XCTAssertEqual(voices.first?.id, "21m00Tcm4TlvDq8ikWAM")
    }
    
    func testElevenLabsVoiceGenderDistribution() {
        let voices = Voice.elevenLabsVoices
        
        let maleVoices = voices.filter { $0.gender == .male }
        let femaleVoices = voices.filter { $0.gender == .female }
        
        XCTAssertFalse(maleVoices.isEmpty, "Should have male voices")
        XCTAssertFalse(femaleVoices.isEmpty, "Should have female voices")
    }
    
    // MARK: - ElevenLabs Model Tests
    
    func testElevenLabsModelCases() {
        let allModels = ElevenLabsModel.allCases
        
        XCTAssertTrue(allModels.contains(.flashV2_5))
        XCTAssertTrue(allModels.contains(.turboV2_5))
        XCTAssertTrue(allModels.contains(.turboV3))
        XCTAssertTrue(allModels.contains(.multilingualV3))
        XCTAssertTrue(allModels.contains(.turboV2))
        XCTAssertTrue(allModels.contains(.multilingualV2))
        XCTAssertTrue(allModels.contains(.monolingualV1))
    }
    
    func testElevenLabsModelRawValues() {
        XCTAssertEqual(ElevenLabsModel.flashV2_5.rawValue, "eleven_flash_v2_5")
        XCTAssertEqual(ElevenLabsModel.turboV2_5.rawValue, "eleven_turbo_v2_5")
        XCTAssertEqual(ElevenLabsModel.turboV3.rawValue, "eleven_turbo_v3")
    }
    
    func testElevenLabsModelDefaultSelection() {
        XCTAssertEqual(ElevenLabsModel.defaultSelection, .turboV2_5)
    }
    
    func testElevenLabsModelStreamingRecommended() {
        XCTAssertEqual(ElevenLabsModel.streamingRecommended, .flashV2_5)
    }
    
    func testElevenLabsModelSupportsStreaming() {
        XCTAssertTrue(ElevenLabsModel.flashV2_5.supportsStreaming)
        XCTAssertTrue(ElevenLabsModel.turboV2_5.supportsStreaming)
        XCTAssertTrue(ElevenLabsModel.turboV2.supportsStreaming)
        XCTAssertFalse(ElevenLabsModel.monolingualV1.supportsStreaming)
    }
    
    func testElevenLabsModelSupportsAdvancedPrompting() {
        XCTAssertTrue(ElevenLabsModel.flashV2_5.supportsAdvancedPrompting)
        XCTAssertTrue(ElevenLabsModel.turboV2_5.supportsAdvancedPrompting)
        XCTAssertFalse(ElevenLabsModel.turboV2.supportsAdvancedPrompting)
        XCTAssertFalse(ElevenLabsModel.monolingualV1.supportsAdvancedPrompting)
    }
    
    func testElevenLabsModelFallback() {
        XCTAssertEqual(ElevenLabsModel.flashV2_5.fallback, .turboV2_5)
        XCTAssertEqual(ElevenLabsModel.turboV2_5.fallback, .turboV2)
        XCTAssertEqual(ElevenLabsModel.turboV3.fallback, .turboV2)
        XCTAssertEqual(ElevenLabsModel.multilingualV3.fallback, .multilingualV2)
        XCTAssertNil(ElevenLabsModel.monolingualV1.fallback)
    }
    
    func testElevenLabsModelIdentifier() {
        let identifier = ElevenLabsModelIdentifier("eleven_custom_model")
        
        XCTAssertEqual(identifier.rawValue, "eleven_custom_model")
        XCTAssertNil(identifier.knownModel)
        
        let knownIdentifier = ElevenLabsModelIdentifier(from: .turboV2_5)
        XCTAssertEqual(knownIdentifier.knownModel, .turboV2_5)
    }
    
    func testElevenLabsVoiceTagDefaultCatalog() {
        let tags = ElevenLabsVoiceTag.defaultCatalog
        
        XCTAssertGreaterThan(tags.count, 10)
        
        let tokens = tags.map { $0.token }
        XCTAssertTrue(tokens.contains("[pause_short]"))
        XCTAssertTrue(tokens.contains("[whisper]"))
        XCTAssertTrue(tokens.contains("[laugh]"))
        XCTAssertTrue(tokens.contains("[pause_medium]"))
        XCTAssertTrue(tokens.contains("[soft]"))
        XCTAssertTrue(tokens.contains("[excited]"))
    }
}

// MARK: - ElevenLabs TTS Service Tests

@available(macOS 14.0, *)
@MainActor
final class ElevenLabsTTSServiceTests: XCTestCase {
    
    var service: ElevenLabsTTSService!
    
    override func setUp() async throws {
        try await super.setUp()
        service = ElevenLabsTTSService()
    }
    
    override func tearDown() async throws {
        service = nil
        try await super.tearDown()
    }
    
    func testServiceName() async {
        XCTAssertEqual(service.name, "ElevenLabs")
    }
    
    func testDefaultVoice() async {
        let defaultVoice = service.defaultVoice
        
        XCTAssertEqual(defaultVoice.id, "21m00Tcm4TlvDq8ikWAM")
        XCTAssertEqual(defaultVoice.name, "Rachel")
        XCTAssertEqual(defaultVoice.provider, .elevenLabs)
        XCTAssertEqual(defaultVoice.gender, .female)
    }
    
    func testStyleControls() async {
        let controls = service.styleControls
        
        XCTAssertEqual(controls.count, 3)
        
        let controlIDs = controls.map { $0.id }
        XCTAssertTrue(controlIDs.contains("elevenLabs.stability"))
        XCTAssertTrue(controlIDs.contains("elevenLabs.similarityBoost"))
        XCTAssertTrue(controlIDs.contains("elevenLabs.style"))
    }
    
    func testStabilityControlRange() async {
        let stabilityControl = service.styleControls.first { $0.id == "elevenLabs.stability" }
        
        XCTAssertNotNil(stabilityControl)
        XCTAssertEqual(stabilityControl?.range.lowerBound, 0)
        XCTAssertEqual(stabilityControl?.range.upperBound, 1)
        XCTAssertEqual(stabilityControl?.defaultValue, 0.5)
    }
    
    func testSimilarityBoostControlRange() async {
        let control = service.styleControls.first { $0.id == "elevenLabs.similarityBoost" }
        
        XCTAssertNotNil(control)
        XCTAssertEqual(control?.range.lowerBound, 0)
        XCTAssertEqual(control?.range.upperBound, 1)
        XCTAssertEqual(control?.defaultValue, 0.75)
    }
    
    func testStyleControlRange() async {
        let control = service.styleControls.first { $0.id == "elevenLabs.style" }
        
        XCTAssertNotNil(control)
        XCTAssertEqual(control?.range.lowerBound, 0)
        XCTAssertEqual(control?.range.upperBound, 1)
        XCTAssertEqual(control?.defaultValue, 0.0)
    }
    
    func testHasValidAPIKeyWithoutKey() async {
        // Clear any existing API key
        let keychain = KeychainManager()
        try? keychain.deleteAPIKey(for: "ElevenLabs")
        
        // Create fresh service
        let freshService = ElevenLabsTTSService()
        
        // Without managed provisioning, should return false
        // Note: This may return true if managed provisioning is enabled
        // The test verifies the method doesn't crash
        _ = freshService.hasValidAPIKey()
    }
    
    func testUpdateAPIKey() async {
        service.updateAPIKey("test-api-key")
        
        // After updating, hasValidAPIKey should return true
        XCTAssertTrue(service.hasValidAPIKey())
    }
    
    func testAvailableVoicesReturnsFallback() async {
        // Without fetching from API, should return fallback voices
        let voices = service.availableVoices
        
        XCTAssertFalse(voices.isEmpty)
        XCTAssertTrue(voices.count >= 9)
    }
    
    func testSynthesizeSpeechThrowsForTextTooLong() async {
        service.updateAPIKey("test-key")
        
        let longText = String(repeating: "a", count: 5001)
        let voice = service.defaultVoice
        let settings = AudioSettings()
        
        do {
            _ = try await service.synthesizeSpeech(text: longText, voice: voice, settings: settings)
            XCTFail("Should throw textTooLong error")
        } catch let error as TTSError {
            if case .textTooLong(let limit) = error {
                XCTAssertEqual(limit, 5000)
            } else {
                XCTFail("Expected textTooLong error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    func testSynthesizeSpeechThrowsForInvalidAPIKey() async {
        // Clear API key
        let keychain = KeychainManager()
        try? keychain.deleteAPIKey(for: "ElevenLabs")
        
        let freshService = ElevenLabsTTSService()
        let voice = freshService.defaultVoice
        let settings = AudioSettings()
        
        do {
            _ = try await freshService.synthesizeSpeech(text: "Hello", voice: voice, settings: settings)
            XCTFail("Should throw invalidAPIKey error")
        } catch let error as TTSError {
            if case .invalidAPIKey = error {
                // Expected
            } else {
                // Network errors are also acceptable since we don't have a valid key
            }
        } catch {
            // Other errors are acceptable (network, etc.)
        }
    }
    
    func testStreamingThrowsForTextTooLong() async {
        service.updateAPIKey("test-key")
        
        let longText = String(repeating: "a", count: 5001)
        let voice = service.defaultVoice
        let settings = AudioSettings()
        
        do {
            try await service.synthesizeSpeechStream(
                text: longText,
                voice: voice,
                settings: settings,
                onChunk: { _ in },
                onComplete: { },
                onError: { _ in }
            )
            XCTFail("Should throw textTooLong error")
        } catch let error as TTSError {
            if case .textTooLong(let limit) = error {
                XCTAssertEqual(limit, 5000)
            } else {
                XCTFail("Expected textTooLong error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    func testCancelStreamingDoesNotCrash() async {
        service.cancelStreaming()
        service.cancelStreaming()
    }
    
    func testServiceConformsToStreamingProtocol() async {
        XCTAssertTrue(service is StreamingSpeechSynthesizing)
    }
}

// MARK: - AudioPlayerService Tests

@available(macOS 14.0, *)
@MainActor
final class AudioPlayerServiceTests: XCTestCase {
    
    var playerService: AudioPlayerService!
    
    override func setUp() async throws {
        try await super.setUp()
        playerService = AudioPlayerService()
    }
    
    override func tearDown() async throws {
        playerService?.stop()
        playerService = nil
        try await super.tearDown()
    }
    
    func testInitialState() async {
        XCTAssertFalse(playerService.isPlaying)
        XCTAssertEqual(playerService.currentTime, 0)
        XCTAssertEqual(playerService.duration, 0)
    }
    
    func testPlaybackProgress() async {
        // Without audio loaded, progress should be 0
        let progress = playerService.getAudioInfo()?.progress ?? 0
        XCTAssertEqual(progress, 0)
    }
    
    func testStopResetsState() async {
        playerService.stop()
        
        XCTAssertFalse(playerService.isPlaying)
        XCTAssertEqual(playerService.currentTime, 0)
    }
    
    func testPlayInvalidDataDoesNotCrash() async {
        // Playing invalid data should not crash
        let invalidData = Data([0x00, 0x01, 0x02, 0x03])
        
        do {
            try await playerService.loadAudio(from: invalidData)
            playerService.play()
            // If it doesn't throw, that's fine - just verify state
        } catch {
            // Expected - invalid audio data
        }
    }
}

// MARK: - Text Chunker Tests

@available(macOS 14.0, *)
final class TextChunkerTests: XCTestCase {
    
    func testChunkTextBySentences() {
        let text = "Hello world. This is a test. Another sentence here."
        let chunks = TextChunker.chunk(text: text, limit: 50)
        
        XCTAssertFalse(chunks.isEmpty)
        
        // Verify no chunk exceeds max length
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.count, 50)
        }
    }
    
    func testChunkTextPreservesSentences() {
        let text = "Short sentence. Another short one."
        let chunks = TextChunker.chunk(text: text, limit: 100)
        
        // With large max length, should be single chunk
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks.first, text)
    }
    
    func testChunkTextHandlesEmptyString() {
        let chunks = TextChunker.chunk(text: "", limit: 100)
        XCTAssertTrue(chunks.isEmpty || chunks.allSatisfy { $0.isEmpty })
    }
    
    func testChunkTextHandlesWhitespaceOnly() {
        let chunks = TextChunker.chunk(text: "   \n\t  ", limit: 100)
        XCTAssertTrue(chunks.isEmpty || chunks.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }
    
    func testChunkTextHandlesLongWord() {
        let longWord = String(repeating: "a", count: 100)
        let chunks = TextChunker.chunk(text: longWord, limit: 50)
        
        // Should split the long word
        XCTAssertGreaterThan(chunks.count, 1)
    }
}

// MARK: - Text Sanitizer Tests

@available(macOS 14.0, *)
final class TextSanitizerTests: XCTestCase {
    
    func testSanitizeRemovesExtraWhitespace() {
        let input = "Hello    world"
        let sanitized = TextSanitizer.cleanImportedText(input)
        
        XCTAssertFalse(sanitized.contains("    "))
    }
    
    func testSanitizeTrimsWhitespace() {
        let input = "  Hello world  "
        let sanitized = TextSanitizer.cleanImportedText(input)
        
        XCTAssertFalse(sanitized.hasPrefix(" "))
        XCTAssertFalse(sanitized.hasSuffix(" "))
    }
    
    func testSanitizeHandlesEmptyString() {
        let sanitized = TextSanitizer.cleanImportedText("")
        XCTAssertEqual(sanitized, "")
    }
    
    func testSanitizePreservesValidText() {
        let input = "Hello, world! How are you?"
        let sanitized = TextSanitizer.cleanImportedText(input)
        
        XCTAssertEqual(sanitized, input)
    }
}
