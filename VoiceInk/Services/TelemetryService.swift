import Foundation
import OSLog
import PostHog

// PostHog Cloud (EU), per ADR-0003. Only the structured fields already recorded by
// SessionMetricRecorder are sent — never audio or transcript text.
enum TelemetryService {
    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "TelemetryService")

    // Project token — PostHog's client-side "project API key" (phc_ prefix), not a secret;
    // designed to be embedded in shipped clients, same as PolarService's organizationId.
    private static let projectToken = "phc_pebugJX9QeVLsVHZAYYtv9qQ4TqgJPuFc6z469sUepiY"
    private static let host = "https://eu.i.posthog.com"

    static func configure() {
        let config = PostHogConfig(projectToken: projectToken, host: host)
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        PostHogSDK.shared.setup(config)
        logger.notice("Telemetry configured")
    }

    static func captureSessionMetric(_ metric: SessionMetric) {
        PostHogSDK.shared.capture("session_metric_recorded", properties: eventProperties(for: metric))
    }

    static func eventProperties(for metric: SessionMetric) -> [String: Any] {
        var properties: [String: Any] = [
            "transcription_id": metric.transcriptionId.uuidString,
            "source": metric.source ?? "unknown",
            "word_count": metric.wordCount,
            "audio_duration": metric.audioDuration,
        ]
        properties["transcription_model_name"] = metric.transcriptionModelName
        properties["transcription_duration"] = metric.transcriptionDuration
        properties["speed_factor"] = metric.speedFactor
        properties["mode_name"] = metric.modeName
        properties["ai_enhancement_model_name"] = metric.aiEnhancementModelName
        properties["enhancement_duration"] = metric.enhancementDuration
        properties["enhancement_estimated_token_count"] = metric.enhancementEstimatedTokenCount
        return properties
    }
}
