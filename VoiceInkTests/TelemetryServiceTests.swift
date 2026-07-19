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

    @Test func detectsItIsRunningUnderXCTest() {
        // This test process IS the exact scenario the configure() guard exists for
        // (VoiceInkTests runs hosted inside VoiceInk.app, see TelemetryService.configure()) —
        // asserting true here is a real, non-tautological check, not a stub.
        #expect(TelemetryService.isRunningTests == true)
    }
}
