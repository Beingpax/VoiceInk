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

    // MARK: - Has this person stopped talking
    //
    // Separate from `.silent`, which asks whether the microphone is dead. Auto-stop was wired to
    // `.silent` and therefore never fired: that state needs every average in a three-second window
    // under 0.06, and any stray sound at all keeps it out of that state indefinitely.

    @Test func nothingIsJudgedQuietBeforeTheWindowFills() {
        let monitor = RecorderInputHealthMonitor()
        feed(monitor, peak: 0.01, average: 0.0, times: 5)
        #expect(!monitor.isQuiet)
    }

    @Test func roomToneCountsAsQuiet() {
        // The case that matters: a room that is not silent, but where nobody is speaking. Averages
        // here sit above the `.silent` threshold, so `.silent` stays false — and auto-stop still
        // has to work.
        // Averages deliberately above the 0.06 silent threshold — this is a room with a fan in
        // it, not a dead microphone — while peaks stay well under anything speech reaches.
        let monitor = RecorderInputHealthMonitor()
        feed(monitor, peak: 0.12, average: 0.08, times: 30)
        #expect(monitor.isQuiet)
        #expect(monitor.health == .clear)
    }

    @Test func aDeadMicrophoneIsAlsoQuiet() {
        let monitor = RecorderInputHealthMonitor()
        feed(monitor, peak: 0.0, average: 0.0, times: 30)
        #expect(monitor.isQuiet)
        #expect(monitor.health == .silent)
    }

    @Test func aWhisperIsNotQuiet() {
        // Whispering is still talking, and stopping the take mid-whisper would be the worst
        // possible failure. Measured whisper peaks start around 0.41, far above the threshold.
        let monitor = RecorderInputHealthMonitor()
        feed(monitor, peak: 0.42, average: 0.15, times: 30)
        #expect(!monitor.isQuiet)
    }

    @Test func normalSpeechIsNotQuiet() {
        let monitor = RecorderInputHealthMonitor()
        feed(monitor, peak: 0.82, average: 0.45, times: 30)
        #expect(!monitor.isQuiet)
    }

    @Test func oneWordInAnOtherwiseQuietWindowCountsAsSpeaking() {
        // Peaks are read as a maximum rather than a proportion, so a single utterance holds the
        // take open for the whole window. Pausing between sentences must not start a countdown.
        let monitor = RecorderInputHealthMonitor()
        feed(monitor, peak: 0.05, average: 0.01, times: 27)
        feed(monitor, peak: 0.70, average: 0.30, times: 3)
        #expect(!monitor.isQuiet)
    }

    @Test func quietResumesOnceTheSpeechLeavesTheWindow() {
        let monitor = RecorderInputHealthMonitor()
        feed(monitor, peak: 0.80, average: 0.45, times: 30)
        #expect(!monitor.isQuiet)

        feed(monitor, peak: 0.05, average: 0.01, times: 30)
        #expect(monitor.isQuiet)
    }

    @Test func resetClearsQuiet() {
        let monitor = RecorderInputHealthMonitor()
        feed(monitor, peak: 0.02, average: 0.0, times: 30)
        #expect(monitor.isQuiet)

        monitor.reset()
        #expect(!monitor.isQuiet)
    }

    @Test func onlyProblemsCountAsProblems() {
        #expect(RecorderInputHealth.tooLoud.isProblem)
        #expect(RecorderInputHealth.silent.isProblem)
        #expect(!RecorderInputHealth.clear.isProblem)
        #expect(!RecorderInputHealth.unknown.isProblem)
    }
}
