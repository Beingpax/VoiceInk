import Foundation
import FluidAudio
import os.log

/// Wraps FluidAudio's OfflineDiarizerManager to implement DiarizationService.
/// The manager accepts a URL directly and handles audio decoding internally,
/// so no manual sample loading is needed.
@MainActor
final class FluidAudioDiarizationService: DiarizationService {
    private let modelManager = FluidAudioDiarizationModelManager()
    private var diarizerManager: OfflineDiarizerManager?

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "FluidAudioDiarizationService")

    var isReady: Bool { diarizerManager != nil }

    func diarize(audioURL: URL) async throws -> [SpeakerSegment] {
        let mgr = try await ensureManager()

        // OfflineDiarizerManager.process(_:URL) handles audio loading, resampling,
        // and returns DiarizationResult with segments typed as [TimedSpeakerSegment].
        let result = try await mgr.process(audioURL)

        return result.segments.map { seg in
            SpeakerSegment(
                speakerLabel: seg.speakerId,
                startSec: Double(seg.startTimeSeconds),
                endSec: Double(seg.endTimeSeconds)
            )
        }
    }

    // MARK: - Private

    private func ensureManager() async throws -> OfflineDiarizerManager {
        if let existing = diarizerManager { return existing }

        try await modelManager.ensureModelsDownloaded()

        // OfflineDiarizerManager.init(config:) is synchronous; prepareModels() is called
        // lazily on first process() call when models == nil, so we don't call it here.
        let config = OfflineDiarizerConfig.default
        let mgr = OfflineDiarizerManager(config: config)
        diarizerManager = mgr
        return mgr
    }
}
