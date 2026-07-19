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

    // VoiceInkTests runs as a hosted test bundle inside the real VoiceInk.app process
    // (TEST_HOST in project.pbxproj), so VoiceInkApp.init() — and this call — genuinely
    // executes on every `xcodebuild test` run. Without this guard, test fixtures leak into
    // production PostHog as real session_metric_recorded events.
    //
    // XCTestConfigurationFilePath alone is NOT reliable: confirmed via PostHog data that at
    // least one post-fix xcodebuild test run still leaked (Swift Testing doesn't always set
    // that env var the way legacy XCTest did). Bundle.allBundles is checked as a second,
    // environment-independent signal — VoiceInkTests.xctest is only ever loaded into the
    // process when tests are actually running, never on a real end-user launch. Either signal
    // being true is enough to disable telemetry (fail toward not sending, not toward sending).
    static var isRunningTests: Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return true
        }
        return Bundle.allBundles.contains { $0.bundlePath.hasSuffix(".xctest") }
    }

    static func configure() {
        guard !isRunningTests else {
            logger.notice("Telemetry disabled under XCTest")
            return
        }

        let config = PostHogConfig(projectToken: projectToken, host: host)
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        // Solo, low-volume usage (ADR-0005) — a handful of dictation sessions between app
        // quits, not a high-throughput client. The default batch size of 20 could sit
        // unflushed for a long time, so flush after every event instead.
        config.flushAt = 1
        PostHogSDK.shared.setup(config)
        logger.notice("Telemetry configured")
    }

    static func captureSessionMetric(_ metric: SessionMetric) {
        // Defense in depth: `configure()` failing to gate setup is exactly the bug that
        // caused the leak this guards against (isRunningTests was true, but PostHogSDK.shared
        // still ended up enabled on at least one run). Checking again here means a single
        // point of failure in configure() can't leak events on its own.
        guard !isRunningTests else {
            logger.notice("Suppressed session_metric_recorded under XCTest (transcription \(metric.transcriptionId.uuidString, privacy: .public))")
            return
        }
        logger.notice("Capturing session_metric_recorded (transcription \(metric.transcriptionId.uuidString, privacy: .public))")
        PostHogSDK.shared.capture("session_metric_recorded", properties: eventProperties(for: metric))
    }

    // The Flag event (CONTEXT.md) — the primary accuracy signal for ADR-0004's fine-tune
    // trigger. Deliberately just a binary marker, joinable to session_metric_recorded via
    // transcription_id — never the transcript text itself.
    static func captureFlagEvent(transcriptionId: UUID) {
        guard !isRunningTests else {
            logger.notice("Suppressed session_flagged under XCTest (transcription \(transcriptionId.uuidString, privacy: .public))")
            return
        }
        logger.notice("Capturing session_flagged (transcription \(transcriptionId.uuidString, privacy: .public))")
        PostHogSDK.shared.capture("session_flagged", properties: flagEventProperties(transcriptionId: transcriptionId))
    }

    static func flagEventProperties(transcriptionId: UUID) -> [String: Any] {
        ["transcription_id": transcriptionId.uuidString]
    }

    static func flush() {
        PostHogSDK.shared.flush()
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
