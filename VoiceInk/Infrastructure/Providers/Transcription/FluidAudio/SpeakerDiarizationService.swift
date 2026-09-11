import FluidAudio
import Foundation
import os.log

/// Runs offline speaker diarization on 16kHz mono samples using FluidAudio's
/// offline pipeline (pyannote-parity AHC clustering — the streaming
/// DiarizerManager over-splits speakers on telephone audio and ignores
/// speaker-count hints). Models are downloaded on first use and the
/// initialized manager is kept for subsequent files.
actor SpeakerDiarizationService {
    static let shared = SpeakerDiarizationService()

    private var diarizer: OfflineDiarizerManager?
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "SpeakerDiarizationService")

    func diarize(samples: [Float]) async throws -> [SpeakerSegment] {
        let manager = try await ensureDiarizer()
        try Task.checkCancellation()

        let result = try await manager.process(audio: samples)
        logger.notice(
            "Diarization completed: \(result.segments.count) segments, \(Set(result.segments.map(\.speakerId)).count) speakers"
        )

        return result.segments.map { segment in
            SpeakerSegment(
                speakerId: segment.speakerId,
                start: TimeInterval(segment.startTimeSeconds),
                end: TimeInterval(segment.endTimeSeconds)
            )
        }
    }

    private func ensureDiarizer() async throws -> OfflineDiarizerManager {
        if let diarizer {
            return diarizer
        }

        logger.notice("Loading offline diarization models")
        do {
            let models = try await OfflineDiarizerModels.load()
            // Another caller may have finished loading while we awaited the download.
            if let diarizer {
                return diarizer
            }
            let manager = OfflineDiarizerManager(config: Self.makeConfig(logger: logger))
            manager.initialize(models: models)
            diarizer = manager
            return manager
        } catch {
            logger.error("Failed to load diarization models: \(error, privacy: .public)")
            throw error
        }
    }

    func cleanup() {
        diarizer = nil
    }

    /// Tuning knobs, overridable without a rebuild (app restart applies them):
    ///   defaults write com.prakashjoshipax.VoiceInk TranscribeDiarizationNumSpeakers -int 2
    ///   defaults write com.prakashjoshipax.VoiceInk TranscribeDiarizationClusteringThreshold -float 0.6
    /// NumSpeakers pins the speaker count when known upfront. The threshold is the
    /// AHC cut distance in [0, 2] — LARGER values merge more and yield FEWER speakers.
    private static func makeConfig(logger: Logger) -> OfflineDiarizerConfig {
        var config = OfflineDiarizerConfig.default
        let defaults = UserDefaults.standard
        if let threshold = defaults.object(forKey: "TranscribeDiarizationClusteringThreshold") as? Double,
            threshold > 0
        {
            config.clustering.threshold = threshold
        }
        let numSpeakers = defaults.integer(forKey: "TranscribeDiarizationNumSpeakers")
        if numSpeakers > 0 {
            config.clustering.numSpeakers = numSpeakers
        }
        logger.notice(
            "Offline diarizer config: threshold=\(config.clustering.threshold, privacy: .public), numSpeakers=\(String(describing: config.clustering.numSpeakers), privacy: .public)"
        )
        return config
    }
}
