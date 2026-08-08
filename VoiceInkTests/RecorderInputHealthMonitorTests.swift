import Testing

@testable import VoiceInk

/// Thresholds here were calibrated from logged takes on real hardware:
///
///     whisper / quiet   peak max 0.41 – 0.47
///     normal speech     peak max 0.75 – 0.88
///     shouting          peak max 0.91 – 1.00
///
/// Two earlier implementations shipped broken because nothing checked them: the first compared
/// normalized 0…1 meter values against dBFS thresholds and reported clipping on every take, and the
/// second required consecutive samples over the line, which bursty speech never produces.
@MainActor
struct RecorderInputHealthMonitorTests {

    private func feed(_ monitor: RecorderInputHealthMonitor, peak: Double, average: Double, times: Int) {
        for _ in 0..<times {
            monitor.ingest(AudioMeter(averagePower: average, peakPower: peak))
        }
    }

    @Test func startsUnknownBeforeTheWindowFills() {
        let monitor = RecorderInputHealthMonitor()
        feed(monitor, peak: 0.8, average: 0.5, times: 5)
        #expect(monitor.health == .unknown)
    }

    @Test func normalSpeechReadsClear() {
        let monitor = RecorderInputHealthMonitor()
        feed(monitor, peak: 0.82, average: 0.45, times: 30)
        #expect(monitor.health == .clear)
    }

    @Test func whisperIsNotFlagged() {
        // A whisper still transcribes fine, so flagging it was wrong. Only true silence counts.
        let monitor = RecorderInputHealthMonitor()
        feed(monitor, peak: 0.45, average: 0.18, times: 30)
        #expect(monitor.health == .clear)
    }

    @Test func sustainedShoutingReadsTooLoud() {
        let monitor = RecorderInputHealthMonitor()
        feed(monitor, peak: 0.95, average: 0.7, times: 30)
        #expect(monitor.health == .tooLoud)
    }

    @Test func oneLoudWordDoesNotTripTooLoud() {
        // The regression that made "too loud" useless in the opposite direction: a single emphatic
        // word must not be reported as shouting.
        let monitor = RecorderInputHealthMonitor()
        feed(monitor, peak: 0.80, average: 0.45, times: 26)
        feed(monitor, peak: 0.97, average: 0.75, times: 4)
        #expect(monitor.health == .clear)
    }

    @Test func silenceReadsAsNotHearingYou() {
        let monitor = RecorderInputHealthMonitor()
        feed(monitor, peak: 0.02, average: 0.01, times: 30)
        #expect(monitor.health == .silent)
    }

    @Test func recoversWhenSpeechResumes() {
        let monitor = RecorderInputHealthMonitor()
        feed(monitor, peak: 0.96, average: 0.7, times: 30)
        #expect(monitor.health == .tooLoud)

        feed(monitor, peak: 0.80, average: 0.45, times: 30)
        #expect(monitor.health == .clear)
    }

    @Test func resetClearsState() {
        let monitor = RecorderInputHealthMonitor()
        feed(monitor, peak: 0.96, average: 0.7, times: 30)
        monitor.reset()
        #expect(monitor.health == .unknown)
    }

    @Test func onlyProblemsCountAsProblems() {
        #expect(RecorderInputHealth.tooLoud.isProblem)
        #expect(RecorderInputHealth.silent.isProblem)
        #expect(!RecorderInputHealth.clear.isProblem)
        #expect(!RecorderInputHealth.unknown.isProblem)
    }
}
