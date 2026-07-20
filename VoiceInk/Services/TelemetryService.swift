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

    // MARK: - transcription_started

    // Fired at the top of TranscriptionPipeline.run(), not at Recorder.startRecording —
    // the pipeline is where "transcription" (as this event is named) actually begins, and
    // it's the point with access to a real transcription id and resolved model, letting this
    // correlate cleanly with transcription_completed/transcription_failed below. A recording
    // that's cancelled before the pipeline runs never emits this, which is correct: no
    // transcription was ever attempted for it.
    static func captureTranscriptionStarted(transcriptionId: UUID, modelName: String?, modeName: String?) {
        guard !isRunningTests else {
            logger.notice(
                "Suppressed transcription_started under XCTest (transcription \(transcriptionId.uuidString, privacy: .public))"
            )
            return
        }
        logger.notice("Capturing transcription_started (transcription \(transcriptionId.uuidString, privacy: .public))")
        PostHogSDK.shared.capture(
            "transcription_started",
            properties: transcriptionStartedEventProperties(
                transcriptionId: transcriptionId, modelName: modelName, modeName: modeName))
    }

    static func transcriptionStartedEventProperties(transcriptionId: UUID, modelName: String?, modeName: String?)
        -> [String: Any]
    {
        var properties: [String: Any] = ["transcription_id": transcriptionId.uuidString]
        properties["model_name"] = modelName
        properties["mode_name"] = modeName
        return properties
    }

    // MARK: - transcription_completed

    // Deliberately redundant with session_metric_recorded — same fields, mirrored via the
    // same eventProperties(for:), but as an explicit success signal distinct from the
    // metrics-oriented event above.
    static func captureTranscriptionCompleted(_ metric: SessionMetric) {
        guard !isRunningTests else {
            logger.notice(
                "Suppressed transcription_completed under XCTest (transcription \(metric.transcriptionId.uuidString, privacy: .public))"
            )
            return
        }
        logger.notice(
            "Capturing transcription_completed (transcription \(metric.transcriptionId.uuidString, privacy: .public))")
        PostHogSDK.shared.capture("transcription_completed", properties: eventProperties(for: metric))
    }

    // MARK: - transcription_failed

    static func captureTranscriptionFailed(transcriptionId: UUID, errorType: String, modelName: String?) {
        guard !isRunningTests else {
            logger.notice(
                "Suppressed transcription_failed under XCTest (transcription \(transcriptionId.uuidString, privacy: .public))"
            )
            return
        }
        logger.notice("Capturing transcription_failed (transcription \(transcriptionId.uuidString, privacy: .public))")
        PostHogSDK.shared.capture(
            "transcription_failed",
            properties: transcriptionFailedEventProperties(
                transcriptionId: transcriptionId, errorType: errorType, modelName: modelName))
    }

    // errorType must be a short category, never the full error description — full messages
    // can carry file paths or API response details (ADR-0003's privacy boundary applies to
    // more than just transcript text).
    static func transcriptionFailedEventProperties(transcriptionId: UUID, errorType: String, modelName: String?)
        -> [String: Any]
    {
        var properties: [String: Any] = [
            "transcription_id": transcriptionId.uuidString,
            "error_type": errorType,
        ]
        properties["model_name"] = modelName
        return properties
    }

    // MARK: - enhancement_triggered / enhancement_skipped

    static func captureEnhancementTriggered(transcriptionId: UUID, modelName: String?, modeName: String?) {
        guard !isRunningTests else {
            logger.notice(
                "Suppressed enhancement_triggered under XCTest (transcription \(transcriptionId.uuidString, privacy: .public))"
            )
            return
        }
        logger.notice("Capturing enhancement_triggered (transcription \(transcriptionId.uuidString, privacy: .public))")
        PostHogSDK.shared.capture(
            "enhancement_triggered",
            properties: enhancementTriggeredEventProperties(
                transcriptionId: transcriptionId, modelName: modelName, modeName: modeName))
    }

    static func enhancementTriggeredEventProperties(transcriptionId: UUID, modelName: String?, modeName: String?)
        -> [String: Any]
    {
        var properties: [String: Any] = ["transcription_id": transcriptionId.uuidString]
        properties["model_name"] = modelName
        properties["mode_name"] = modeName
        return properties
    }

    // reason is whatever the call site can actually distinguish — "not_configured" (no LLM
    // provider set up), "disabled_for_mode" (enhancement off for the active mode/config), or
    // "short_text_skip" (below the configured word-count threshold). Fired on every session
    // where enhancement could have run but didn't, so opt-in rate = triggered / (triggered +
    // skipped), not just a count of one side.
    static func captureEnhancementSkipped(transcriptionId: UUID, reason: String, modeName: String?) {
        guard !isRunningTests else {
            logger.notice(
                "Suppressed enhancement_skipped under XCTest (transcription \(transcriptionId.uuidString, privacy: .public))"
            )
            return
        }
        logger.notice("Capturing enhancement_skipped (transcription \(transcriptionId.uuidString, privacy: .public))")
        PostHogSDK.shared.capture(
            "enhancement_skipped",
            properties: enhancementSkippedEventProperties(
                transcriptionId: transcriptionId, reason: reason, modeName: modeName))
    }

    static func enhancementSkippedEventProperties(transcriptionId: UUID, reason: String, modeName: String?)
        -> [String: Any]
    {
        var properties: [String: Any] = [
            "transcription_id": transcriptionId.uuidString,
            "reason": reason,
        ]
        properties["mode_name"] = modeName
        return properties
    }

    // MARK: - enhancement_failed

    // The third leg of the enhancement funnel: triggered (ran and succeeded), skipped (never
    // attempted, with reason), failed (attempted but the provider errored). Without this event
    // a provider that always errors — e.g. Apple Intelligence mid model-download — is
    // indistinguishable in PostHog from one that works. model_name "on-device" = Apple
    // Intelligence.
    static func captureEnhancementFailed(
        transcriptionId: UUID, modelName: String?, modeName: String?, errorDescription: String
    ) {
        guard !isRunningTests else {
            logger.notice(
                "Suppressed enhancement_failed under XCTest (transcription \(transcriptionId.uuidString, privacy: .public))"
            )
            return
        }
        logger.notice("Capturing enhancement_failed (transcription \(transcriptionId.uuidString, privacy: .public))")
        PostHogSDK.shared.capture(
            "enhancement_failed",
            properties: enhancementFailedEventProperties(
                transcriptionId: transcriptionId, modelName: modelName, modeName: modeName,
                errorDescription: errorDescription))
    }

    static func enhancementFailedEventProperties(
        transcriptionId: UUID, modelName: String?, modeName: String?, errorDescription: String
    ) -> [String: Any] {
        var properties: [String: Any] = [
            "transcription_id": transcriptionId.uuidString,
            // Bounded so a long provider stack trace can't blow up event size.
            "error_description": String(errorDescription.prefix(200)),
        ]
        properties["model_name"] = modelName
        properties["mode_name"] = modeName
        return properties
    }

    // MARK: - transcription_copied

    static func captureTranscriptionCopied(transcriptionId: UUID, source: String) {
        guard !isRunningTests else {
            logger.notice(
                "Suppressed transcription_copied under XCTest (transcription \(transcriptionId.uuidString, privacy: .public))"
            )
            return
        }
        logger.notice("Capturing transcription_copied (transcription \(transcriptionId.uuidString, privacy: .public))")
        PostHogSDK.shared.capture(
            "transcription_copied",
            properties: transcriptionCopiedEventProperties(transcriptionId: transcriptionId, source: source))
    }

    static func transcriptionCopiedEventProperties(transcriptionId: UUID, source: String) -> [String: Any] {
        ["transcription_id": transcriptionId.uuidString, "source": source]
    }

    // MARK: - transcription_discarded

    // transcriptionId is optional: a recording cancelled before the pipeline creates/completes
    // its Transcription record has nothing to key on beyond the fact that it was discarded.
    static func captureTranscriptionDiscarded(transcriptionId: UUID?, reason: String) {
        guard !isRunningTests else {
            logger.notice("Suppressed transcription_discarded under XCTest (reason: \(reason, privacy: .public))")
            return
        }
        logger.notice("Capturing transcription_discarded (reason: \(reason, privacy: .public))")
        PostHogSDK.shared.capture(
            "transcription_discarded",
            properties: transcriptionDiscardedEventProperties(transcriptionId: transcriptionId, reason: reason))
    }

    static func transcriptionDiscardedEventProperties(transcriptionId: UUID?, reason: String) -> [String: Any] {
        var properties: [String: Any] = ["reason": reason]
        properties["transcription_id"] = transcriptionId?.uuidString
        return properties
    }

    // MARK: - model_switched

    static func captureModelSwitched(fromModel: String?, toModel: String) {
        guard !isRunningTests else {
            logger.notice("Suppressed model_switched under XCTest (to: \(toModel, privacy: .public))")
            return
        }
        logger.notice("Capturing model_switched (to: \(toModel, privacy: .public))")
        PostHogSDK.shared.capture(
            "model_switched", properties: modelSwitchedEventProperties(fromModel: fromModel, toModel: toModel))
    }

    static func modelSwitchedEventProperties(fromModel: String?, toModel: String) -> [String: Any] {
        var properties: [String: Any] = ["to_model": toModel]
        properties["from_model"] = fromModel
        return properties
    }
}
