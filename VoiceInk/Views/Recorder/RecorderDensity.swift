import Foundation

/// How much the recorder panel is currently saying.
///
/// Deliberately *not* a setting. Density is judged per take from live conditions — the panel earns
/// its size rather than being told what size to be.
enum RecorderDensity: Int, Comparable {
    /// Controls only.
    case minimal = 0
    /// Adds the Signal Strip when it has something to report.
    case standard = 1
    /// Live transcript always on.
    case expanded = 2

    static func < (lhs: RecorderDensity, rhs: RecorderDensity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Judges density from live conditions, and remembers the highest level reached during a take.
///
/// Density can grow mid-take but never shrinks mid-take: a panel that collapses while you are
/// looking at it is worse than one that is briefly larger than it needs to be. The ratchet resets
/// when the take ends.
@MainActor
@Observable
final class RecorderDensityJudge {
    private(set) var density: RecorderDensity = .minimal

    /// Highest density reached in the current take.
    private var ratchet: RecorderDensity = .minimal
    private var takeStartedAt: Date?

    /// A take running longer than this is where people lose their place, so show them the text.
    private let longTakeThreshold: TimeInterval = 45

    /// Modes used fewer than this many times still get the fuller panel, to teach what they do.
    static let newModeUseThreshold = 3

    func endTake() {
        ratchet = .minimal
        density = .minimal
        takeStartedAt = nil
    }

    func evaluate(_ inputs: Inputs) {
        if inputs.isRecording, takeStartedAt == nil {
            takeStartedAt = inputs.now
        }
        if !inputs.isRecording {
            takeStartedAt = nil
        }

        var judged = RecorderDensity.minimal

        // Live transcript is the reason you turned realtime on.
        if inputs.isRealtimeTranscriptionEnabled, inputs.showLiveTranscript {
            judged = .expanded
        }

        // Long dictation: show the text so you can see where you are.
        if let start = takeStartedAt, inputs.now.timeIntervalSince(start) >= longTakeThreshold {
            judged = max(judged, .expanded)
        }

        // Anything worth reporting earns the strip.
        if inputs.hasHealthProblem
            || !inputs.contextIsEmpty
            || inputs.isUnfamiliarMode
            || inputs.deviceChangedDuringTake
        {
            judged = max(judged, .standard)
        }

        ratchet = max(ratchet, judged)
        density = inputs.isRecording ? ratchet : judged
    }

    struct Inputs {
        var now: Date = .now
        var isRecording: Bool
        var hasHealthProblem: Bool
        var contextIsEmpty: Bool
        var isRealtimeTranscriptionEnabled: Bool
        var showLiveTranscript: Bool
        var isUnfamiliarMode: Bool
        var deviceChangedDuringTake: Bool
    }
}

/// Tracks how often each mode has been used, so a freshly created mode can show more of itself
/// for the first few takes and then get out of the way.
@MainActor
enum RecorderModeFamiliarity {
    private static let keyPrefix = "recorderModeUseCount."

    static func useCount(for modeID: UUID) -> Int {
        UserDefaults.standard.integer(forKey: keyPrefix + modeID.uuidString)
    }

    static func isUnfamiliar(_ modeID: UUID?) -> Bool {
        guard let modeID else { return false }
        return useCount(for: modeID) < RecorderDensityJudge.newModeUseThreshold
    }

    static func recordUse(of modeID: UUID?) {
        guard let modeID else { return }
        let key = keyPrefix + modeID.uuidString
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: key) + 1, forKey: key)
    }
}
