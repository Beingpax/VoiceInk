import OSLog
import SwiftUI

// MARK: - Input health

/// What the microphone signal looks like right now.
///
/// The visualizer already moves with volume, but a dead mic and a quiet room look the same until
/// the transcript comes back empty. This turns the same meter data into something actionable.
enum RecorderInputHealth: Equatable {
    case unknown
    case clear
    /// Nothing usable is reaching the microphone.
    case silent
    /// Consistently hot enough to risk distortion. In practice this is shouting or a mic too close.
    case tooLoud

    var isProblem: Bool { self == .silent || self == .tooLoud }

    var label: LocalizedStringKey? {
        switch self {
        case .unknown: return nil
        case .clear: return "Clear"
        case .silent: return "Not hearing you"
        case .tooLoud: return "Too loud — ease off"
        }
    }

    var tint: Color {
        switch self {
        case .unknown, .clear: return AppTheme.Recorder.healthOK
        case .silent, .tooLoud: return AppTheme.Recorder.healthBad
        }
    }

    /// Plain string for the ambient caption, which has no chip to put a LocalizedStringKey in.
    var problemMessage: String? {
        switch self {
        case .silent: return String(localized: "Not hearing you")
        case .tooLoud: return String(localized: "Too loud — ease off")
        case .unknown, .clear: return nil
        }
    }
}

/// Classifies the microphone signal over a rolling window.
///
/// Calibrated from logged takes on real hardware rather than assumed:
///
///     whisper / quiet   peak max 0.41 – 0.47
///     normal speech     peak max 0.75 – 0.88
///     shouting          peak max 0.91 – 1.00
///
/// Two earlier attempts failed for the same structural reason: they required N *consecutive*
/// samples above a threshold. Speech is bursty, so peaks touch the top for a moment and never
/// sustain, and the condition never fired. This counts the *proportion* of loud samples in a
/// window instead, which is what "shouting" actually looks like in the data.
@MainActor
@Observable
final class RecorderInputHealthMonitor {
    private(set) var health: RecorderInputHealth = .unknown

    /// Whether nobody is currently speaking. Distinct from `.silent`, and the distinction matters:
    /// `.silent` answers "is this microphone dead", `isQuiet` answers "has this person stopped
    /// talking". Auto-stop needs the second and was wired to the first, which is why it never
    /// fired — `.silent` demands that *every* average in a three-second window sit under 0.06, and
    /// a fan, a keystroke or a voice two rooms away is enough to keep it out of that state forever.
    ///
    /// Peaks are the right signal here. Speech is loud in the peaks even when the average is low —
    /// a whisper still reaches 0.41 — while room tone stays far below. So one word anywhere in the
    /// window is enough to say someone is still talking.
    private(set) var isQuiet = false

    /// Above this a sample counts as hot. Sits above the 0.88 ceiling of normal speech and below
    /// the 0.91 floor of shouting.
    private let loudSampleThreshold: Double = 0.90
    /// Shouting keeps peaks hot much of the time; a single emphatic word does not.
    private let loudFractionTrigger: Double = 0.35
    /// Below this a sample counts as effectively silent.
    private let silentSampleThreshold: Double = 0.06
    /// Peak below which nothing in the window can have been speech. Sits well under the 0.41 floor
    /// measured for a whisper, and well above ordinary room tone.
    private let speechPeakThreshold: Double = 0.15

    /// 3 seconds at the 10Hz sample rate. Long enough to ignore one loud word, short enough to
    /// react while the take is still running.
    private let windowSize = 30
    /// Do not judge anything until the window has filled, so the opening silence of every take is
    /// not immediately reported as a dead microphone.
    private let minimumSamplesBeforeJudging = 20

    private var peakWindow: [Double] = []
    private var averageWindow: [Double] = []

    private static let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink", category: "RecorderInputHealth")
    private static let isDebugEnabled = UserDefaults.standard.bool(forKey: "RecorderMeterDebug")
    private var observedPeakMax: Double = 0
    private var observedLoudFraction: Double = 0

    func reset() {
        if Self.isDebugEnabled, observedPeakMax > 0 {
            Self.logger.notice(
                "take ended — peak max \(self.observedPeakMax, format: .fixed(precision: 3)), loud fraction \(self.observedLoudFraction, format: .fixed(precision: 3)), final \(String(describing: self.health), privacy: .public)"
            )
        }
        health = .unknown
        isQuiet = false
        peakWindow.removeAll()
        averageWindow.removeAll()
        observedPeakMax = 0
        observedLoudFraction = 0
    }

    func ingest(_ meter: AudioMeter) {
        peakWindow.append(meter.peakPower)
        averageWindow.append(meter.averagePower)
        if peakWindow.count > windowSize {
            peakWindow.removeFirst()
            averageWindow.removeFirst()
        }

        observedPeakMax = max(observedPeakMax, meter.peakPower)

        guard peakWindow.count >= minimumSamplesBeforeJudging else { return }

        isQuiet = (peakWindow.max() ?? 0) < speechPeakThreshold

        let loudFraction =
            Double(peakWindow.filter { $0 >= loudSampleThreshold }.count) / Double(peakWindow.count)
        observedLoudFraction = max(observedLoudFraction, loudFraction)

        let hasAnySignal = averageWindow.contains { $0 > silentSampleThreshold }

        if loudFraction >= loudFractionTrigger {
            health = .tooLoud
        } else if !hasAnySignal {
            health = .silent
        } else {
            health = .clear
        }
    }
}

// MARK: - Context

/// What will be sent along with the audio. Mirrors `RecordingContextSnapshot`, reduced to what the
/// panel needs to display.
struct RecorderContextSummary: Equatable {
    var selectedWordCount: Int?
    var hasScreenText: Bool = false
    var hasClipboardText: Bool = false

    static let empty = RecorderContextSummary()

    var isEmpty: Bool {
        selectedWordCount == nil && !hasScreenText && !hasClipboardText
    }

    init(selectedWordCount: Int? = nil, hasScreenText: Bool = false, hasClipboardText: Bool = false) {
        self.selectedWordCount = selectedWordCount
        self.hasScreenText = hasScreenText
        self.hasClipboardText = hasClipboardText
    }

    init(snapshot: RecordingContextSnapshot) {
        if let selected = snapshot.selectedText {
            selectedWordCount = selected.split(whereSeparator: \.isWhitespace).count
        }
        hasScreenText = snapshot.screenText != nil
        hasClipboardText = snapshot.clipboardText != nil
    }
}

// MARK: - The strip

/// Input health and attached context in one row, split by a divider.
///
/// The two are the same question at different moments — *can I trust this take?* Health is about
/// the signal coming in; context is about what goes out with it. Each side owns a colour family
/// (green/red for health, blue for context) that nothing else in the recorder uses, so the split
/// reads without labels.
///
/// The strip only renders when it has something non-obvious to say — see `shouldRender`.
struct RecorderSignalStrip: View {
    let health: RecorderInputHealth
    let context: RecorderContextSummary
    let deviceName: String?
    /// When counting down to an auto-stop, that replaces the health chip — it is strictly more
    /// urgent than the condition that caused it.
    var silenceCountdown: Int?
    var onKeepRecording: () -> Void = {}

    /// A healthy take with nothing attached earns no space. Degradation does.
    static func shouldRender(
        health: RecorderInputHealth,
        context: RecorderContextSummary,
        silenceCountdown: Int? = nil
    ) -> Bool {
        silenceCountdown != nil || health.isProblem || !context.isEmpty
    }

    var body: some View {
        HStack(spacing: 6) {
            healthSide

            if !context.isEmpty {
                Rectangle()
                    .fill(AppTheme.Recorder.separator)
                    .frame(width: 1, height: 12)

                contextSide
            }

            Spacer(minLength: 0)

            // The device is named only when it is likely the culprit — a quiet or dead input is
            // usually the wrong microphone being selected.
            if health.isProblem, let deviceName {
                Text(deviceName)
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.Recorder.labelTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(Color.black.opacity(0.24))
    }

    @ViewBuilder
    private var healthSide: some View {
        if let silenceCountdown {
            RecorderSilenceCountdown(
                secondsRemaining: silenceCountdown,
                onKeepRecording: onKeepRecording
            )
        } else if let label = health.label {
            SignalChip(text: label, tint: health.tint, isFilled: health.isProblem)
        }
    }

    private var contextSide: some View {
        HStack(spacing: 4) {
            if let words = context.selectedWordCount {
                SignalChip(
                    text: "Selection · \(words) words",
                    tint: AppTheme.Recorder.context,
                    isFilled: true
                )
            }
            if context.hasScreenText {
                SignalChip(text: "Screen", tint: AppTheme.Recorder.context, isFilled: true)
            }
            if context.hasClipboardText {
                SignalChip(text: "Clipboard", tint: AppTheme.Recorder.context, isFilled: true)
            }
        }
    }
}

private struct SignalChip: View {
    let text: LocalizedStringKey
    let tint: Color
    var isFilled: Bool

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(tint)
                .frame(width: 4, height: 4)

            Text(text)
                .font(.system(size: 9.5, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(isFilled ? tint : AppTheme.Recorder.labelSecondary)
        }
        .padding(.horizontal, 6)
        .frame(height: 16)
        .background(Capsule().fill(tint.opacity(isFilled ? 0.16 : 0.10)))
    }
}
