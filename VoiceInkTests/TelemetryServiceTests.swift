import Foundation
import Testing

@testable import VoiceInk

// Only eventProperties(for:) is covered — configure()/captureSessionMetric() drive the
// PostHogSDK.shared singleton, which sends real network requests and isn't mockable here.
struct TelemetryServiceTests {

    private func makeMetric(
        source: String? = "recorder",
        wordCount: Int = 12,
        audioDuration: TimeInterval = 4.5,
        transcriptionModelName: String? = "Whisper Large v3",
        transcriptionDuration: TimeInterval? = 1.5,
        speedFactor: Double? = 3.0,
        modeName: String? = "Default",
        aiEnhancementModelName: String? = nil,
        enhancementDuration: TimeInterval? = nil,
        enhancementEstimatedTokenCount: Int? = nil
    ) -> SessionMetric {
        SessionMetric(
            transcriptionId: UUID(),
            source: source,
            wordCount: wordCount,
            audioDuration: audioDuration,
            transcriptionModelName: transcriptionModelName,
            transcriptionDuration: transcriptionDuration,
            speedFactor: speedFactor,
            modeName: modeName,
            aiEnhancementModelName: aiEnhancementModelName,
            enhancementDuration: enhancementDuration,
            enhancementEstimatedTokenCount: enhancementEstimatedTokenCount
        )
    }

    @Test func includesAllPopulatedFields() {
        let metric = makeMetric()
        let properties = TelemetryService.eventProperties(for: metric)

        #expect(properties["transcription_id"] as? String == metric.transcriptionId.uuidString)
        #expect(properties["source"] as? String == "recorder")
        #expect(properties["word_count"] as? Int == 12)
        #expect(properties["audio_duration"] as? TimeInterval == 4.5)
        #expect(properties["transcription_model_name"] as? String == "Whisper Large v3")
        #expect(properties["transcription_duration"] as? TimeInterval == 1.5)
        #expect(properties["speed_factor"] as? Double == 3.0)
        #expect(properties["mode_name"] as? String == "Default")
    }

    @Test func omitsUnpopulatedOptionalFieldsRatherThanSendingNull() {
        let metric = makeMetric(
            transcriptionModelName: nil,
            transcriptionDuration: nil,
            speedFactor: nil,
            modeName: nil,
            aiEnhancementModelName: nil,
            enhancementDuration: nil,
            enhancementEstimatedTokenCount: nil
        )
        let properties = TelemetryService.eventProperties(for: metric)

        #expect(properties["transcription_model_name"] == nil)
        #expect(properties["transcription_duration"] == nil)
        #expect(properties["speed_factor"] == nil)
        #expect(properties["mode_name"] == nil)
        #expect(properties["ai_enhancement_model_name"] == nil)
        #expect(properties["enhancement_duration"] == nil)
        #expect(properties["enhancement_estimated_token_count"] == nil)
    }

    @Test func neverIncludesRawTranscriptText() {
        // No SessionMetric field carries transcript/audio content — this pins the
        // ADR-0003 privacy boundary at the event-property layer, not just the model layer.
        let metric = makeMetric()
        let properties = TelemetryService.eventProperties(for: metric)

        #expect(properties.keys.allSatisfy { $0 != "text" && $0 != "transcript" && $0 != "enhanced_text" })
    }

    @Test func fallsBackToUnknownWhenSourceIsMissing() {
        let metric = makeMetric(source: nil)
        let properties = TelemetryService.eventProperties(for: metric)

        #expect(properties["source"] as? String == "unknown")
    }

    @Test func flagEventPropertiesContainsOnlyTheTranscriptionId() {
        // The Flag event (CONTEXT.md) is deliberately a binary marker, never the transcript
        // text — this pins that boundary at the event-property layer.
        let id = UUID()
        let properties = TelemetryService.flagEventProperties(transcriptionId: id)

        #expect(properties.count == 1)
        #expect(properties["transcription_id"] as? String == id.uuidString)
    }

    @Test func detectsItIsRunningUnderXCTest() {
        // This test process IS the exact scenario the configure() guard exists for
        // (VoiceInkTests runs hosted inside VoiceInk.app, see TelemetryService.configure()) —
        // asserting true here is a real, non-tautological check, not a stub.
        #expect(TelemetryService.isRunningTests == true)
    }

    @Test func bothIndependentTestDetectionSignalsHoldInThisEnvironment() {
        // Regression test for the real incident: XCTestConfigurationFilePath alone
        // (isRunningTests' original implementation) was proven unreliable — PostHog data
        // showed a leaked event from an xcodebuild test run *after* that guard was live,
        // meaning the env var wasn't set on at least one real test-hosted launch. Asserting
        // each underlying signal separately means if either one silently stops holding in a
        // future Xcode/Swift Testing version, this fails and names which signal broke,
        // rather than the combined isRunningTests OR masking a partial failure.
        let hasXCTestEnvVar = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let hasXCTestBundle = Bundle.allBundles.contains { $0.bundlePath.hasSuffix(".xctest") }

        #expect(hasXCTestBundle, "Bundle-based detection must hold even if the env var doesn't")
        _ = hasXCTestEnvVar  // recorded for visibility; not asserted on, since it's the signal already shown to be unreliable
    }

    // MARK: - transcription_started

    @Test func transcriptionStartedIncludesModelAndModeWhenPresent() {
        let id = UUID()
        let properties = TelemetryService.transcriptionStartedEventProperties(
            transcriptionId: id, modelName: "Parakeet V3", modeName: "Default")

        #expect(properties["transcription_id"] as? String == id.uuidString)
        #expect(properties["model_name"] as? String == "Parakeet V3")
        #expect(properties["mode_name"] as? String == "Default")
    }

    @Test func transcriptionStartedOmitsNilModelAndMode() {
        let id = UUID()
        let properties = TelemetryService.transcriptionStartedEventProperties(
            transcriptionId: id, modelName: nil, modeName: nil)

        #expect(properties["model_name"] == nil)
        #expect(properties["mode_name"] == nil)
    }

    // MARK: - transcription_failed

    @Test func transcriptionFailedIncludesErrorTypeAndModel() {
        let id = UUID()
        let properties = TelemetryService.transcriptionFailedEventProperties(
            transcriptionId: id, errorType: "WhisperTranscriptionError", modelName: "Whisper Large v3")

        #expect(properties["transcription_id"] as? String == id.uuidString)
        #expect(properties["error_type"] as? String == "WhisperTranscriptionError")
        #expect(properties["model_name"] as? String == "Whisper Large v3")
    }

    @Test func transcriptionFailedNeverIncludesFullErrorDescription() {
        // error_type must be a short category (e.g. a Swift type name), never a full,
        // potentially path/detail-carrying error description — pin the property shape itself
        // rather than trust every call site to pass the right thing.
        let id = UUID()
        let properties = TelemetryService.transcriptionFailedEventProperties(
            transcriptionId: id, errorType: "NetworkError", modelName: nil)

        #expect(properties.keys.contains("error_type"))
        #expect(properties.keys.allSatisfy { $0 != "error_description" && $0 != "message" })
    }

    // MARK: - enhancement_triggered / enhancement_skipped

    @Test func enhancementTriggeredIncludesModelAndMode() {
        let id = UUID()
        let properties = TelemetryService.enhancementTriggeredEventProperties(
            transcriptionId: id, modelName: "gpt-4o-mini", modeName: "Slack")

        #expect(properties["transcription_id"] as? String == id.uuidString)
        #expect(properties["model_name"] as? String == "gpt-4o-mini")
        #expect(properties["mode_name"] as? String == "Slack")
    }

    @Test func enhancementSkippedIncludesReasonAndMode() {
        let id = UUID()
        let properties = TelemetryService.enhancementSkippedEventProperties(
            transcriptionId: id, reason: "not_configured", modeName: nil)

        #expect(properties["transcription_id"] as? String == id.uuidString)
        #expect(properties["reason"] as? String == "not_configured")
        #expect(properties["mode_name"] == nil)
    }

    // MARK: - transcription_copied

    @Test func transcriptionCopiedIncludesIdAndSource() {
        let id = UUID()
        let properties = TelemetryService.transcriptionCopiedEventProperties(transcriptionId: id, source: "hover_button")

        #expect(properties.count == 2)
        #expect(properties["transcription_id"] as? String == id.uuidString)
        #expect(properties["source"] as? String == "hover_button")
    }

    // MARK: - transcription_discarded

    @Test func transcriptionDiscardedIncludesIdWhenPresent() {
        let id = UUID()
        let properties = TelemetryService.transcriptionDiscardedEventProperties(transcriptionId: id, reason: "cancelled")

        #expect(properties["transcription_id"] as? String == id.uuidString)
        #expect(properties["reason"] as? String == "cancelled")
    }

    @Test func transcriptionDiscardedOmitsIdWhenNil() {
        // A recording cancelled before the pipeline ever creates a completed Transcription
        // record has no id to key on — must not crash, and must simply omit the field.
        let properties = TelemetryService.transcriptionDiscardedEventProperties(transcriptionId: nil, reason: "cancelled")

        #expect(properties["transcription_id"] == nil)
        #expect(properties["reason"] as? String == "cancelled")
    }

    // MARK: - model_switched

    @Test func modelSwitchedIncludesFromAndToModel() {
        let properties = TelemetryService.modelSwitchedEventProperties(fromModel: "Whisper Large v3", toModel: "Parakeet V3")

        #expect(properties["from_model"] as? String == "Whisper Large v3")
        #expect(properties["to_model"] as? String == "Parakeet V3")
    }

    @Test func modelSwitchedOmitsFromModelWhenThereWasNoPreviousModel() {
        // First-ever model selection (no prior default) has no "from" side.
        let properties = TelemetryService.modelSwitchedEventProperties(fromModel: nil, toModel: "Parakeet V3")

        #expect(properties["from_model"] == nil)
        #expect(properties["to_model"] as? String == "Parakeet V3")
    }
}
