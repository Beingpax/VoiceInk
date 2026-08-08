import Foundation
import Testing

@testable import VoiceInk

/// The estimate replaces an indeterminate spinner with a number, which means a wrong number is
/// worse than no number. Most of what matters here is when it declines to predict at all.
@MainActor
struct RecorderProcessingEstimateTests {

    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func history(
        sessions: Int,
        speedFactor: Double? = nil,
        averageDuration: TimeInterval? = nil
    ) -> ModelPerformanceSummary {
        ModelPerformanceSummary(
            kind: .transcription,
            name: "parakeet-v3",
            sessionCount: sessions,
            averageProcessingDuration: averageDuration,
            averageSpeedFactor: speedFactor
        )
    }

    // MARK: - When it refuses to predict

    @Test func noModelMeansNoEstimate() {
        let estimate = RecorderProcessingEstimate()
        estimate.begin(audioDuration: 40, modelName: nil, performance: nil, now: t0)
        #expect(!estimate.hasEstimate)
        #expect(estimate.basis == nil)
    }

    @Test func noHistoryMeansNoEstimate() {
        let estimate = RecorderProcessingEstimate()
        estimate.begin(audioDuration: 40, modelName: "parakeet-v3", performance: nil, now: t0)
        #expect(!estimate.hasEstimate)
    }

    @Test func tooFewSessionsMeansNoEstimate() {
        // Two runs of a model is noise, not an average.
        let estimate = RecorderProcessingEstimate()
        estimate.begin(
            audioDuration: 40,
            modelName: "parakeet-v3",
            performance: history(sessions: 2, speedFactor: 3),
            now: t0
        )
        #expect(!estimate.hasEstimate)
    }

    @Test func aNonsenseSpeedFactorIsNotUsed() {
        let estimate = RecorderProcessingEstimate()
        estimate.begin(
            audioDuration: 40,
            modelName: "parakeet-v3",
            performance: history(sessions: 10, speedFactor: 0),
            now: t0
        )
        #expect(!estimate.hasEstimate)
    }

    @Test func aZeroLengthTakeIsNotPredicted() {
        let estimate = RecorderProcessingEstimate()
        estimate.begin(
            audioDuration: 0,
            modelName: "parakeet-v3",
            performance: history(sessions: 10, speedFactor: 3),
            now: t0
        )
        #expect(!estimate.hasEstimate)
    }

    // MARK: - When it does

    @Test func itDividesTheTakeByTheSpeedFactor() {
        // 40s of audio at 3x realtime is ~13.3s of work.
        let estimate = RecorderProcessingEstimate()
        estimate.begin(
            audioDuration: 40,
            modelName: "parakeet-v3",
            performance: history(sessions: 10, speedFactor: 3),
            now: t0
        )
        #expect(estimate.hasEstimate)

        estimate.tick(now: t0)
        #expect(estimate.remaining != nil)
        #expect(abs(estimate.remaining! - 40.0 / 3.0) < 0.001)
    }

    @Test func itFallsBackToTheAverageWhenThereIsNoSpeedFactor() {
        let estimate = RecorderProcessingEstimate()
        estimate.begin(
            audioDuration: 40,
            modelName: "parakeet-v3",
            performance: history(sessions: 10, speedFactor: nil, averageDuration: 9),
            now: t0
        )
        #expect(estimate.hasEstimate)

        estimate.tick(now: t0.addingTimeInterval(3))
        #expect(abs(estimate.remaining! - 6) < 0.001)
    }

    @Test func itNamesWhereTheNumberCameFrom() {
        // The number is a guess, so it has to be attributable rather than mysterious.
        let estimate = RecorderProcessingEstimate()
        estimate.begin(
            audioDuration: 40,
            modelName: "parakeet-v3",
            performance: history(sessions: 10, speedFactor: 3),
            now: t0
        )
        #expect(estimate.basis?.contains("parakeet-v3") == true)
    }

    @Test func progressTracksElapsedTime() {
        let estimate = RecorderProcessingEstimate()
        estimate.begin(
            audioDuration: 30,
            modelName: "parakeet-v3",
            performance: history(sessions: 10, speedFactor: 3),
            now: t0
        )

        estimate.tick(now: t0.addingTimeInterval(5))
        #expect(abs(estimate.progress - 0.5) < 0.001)
    }

    @Test func progressStopsShortOfComplete() {
        // A bar parked at 100% while the model is still working reads as hung. Overrunning the
        // estimate is normal, so the cap is load-bearing, not cosmetic.
        let estimate = RecorderProcessingEstimate()
        estimate.begin(
            audioDuration: 30,
            modelName: "parakeet-v3",
            performance: history(sessions: 10, speedFactor: 3),
            now: t0
        )

        estimate.tick(now: t0.addingTimeInterval(600))
        #expect(estimate.progress == 0.97)
        #expect(estimate.remaining == 0)
    }

    @Test func tickWithoutAnEstimateDoesNothing() {
        let estimate = RecorderProcessingEstimate()
        estimate.begin(audioDuration: 40, modelName: nil, performance: nil, now: t0)
        estimate.tick(now: t0.addingTimeInterval(10))
        #expect(estimate.progress == 0)
        #expect(estimate.remaining == nil)
    }

    @Test func endClearsEverything() {
        let estimate = RecorderProcessingEstimate()
        estimate.begin(
            audioDuration: 30,
            modelName: "parakeet-v3",
            performance: history(sessions: 10, speedFactor: 3),
            now: t0
        )
        estimate.tick(now: t0.addingTimeInterval(5))

        estimate.end()
        #expect(!estimate.hasEstimate)
        #expect(estimate.progress == 0)
        #expect(estimate.remaining == nil)
        #expect(estimate.basis == nil)

        // And a stale estimate cannot resume ticking on the next take.
        estimate.tick(now: t0.addingTimeInterval(6))
        #expect(estimate.progress == 0)
    }
}
