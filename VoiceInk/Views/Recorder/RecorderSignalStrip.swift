import SwiftUI

// MARK: - Input health

/// What the microphone signal looks like right now.
///
/// The visualizer already moves with volume, but a dead mic and a quiet room look the same until
/// the transcript comes back empty. This turns the same meter data into something actionable.
enum RecorderInputHealth: Equatable {
    case unknown
    case clear
    case quiet
    case clipping

    var isProblem: Bool { self == .quiet || self == .clipping }

    var label: LocalizedStringKey? {
        switch self {
        case .unknown: return nil
        case .clear: return "Clear"
        case .quiet: return "Barely hearing you"
        case .clipping: return "Clipping — move back"
        }
    }

    var tint: Color {
        switch self {
        case .unknown, .clear: return AppTheme.Recorder.healthOK
        case .quiet, .clipping: return AppTheme.Recorder.healthBad
        }
    }
}

/// Samples the audio meter over a short window and classifies it.
///
/// Deliberately slow to alarm and quick to clear: a single loud syllable is not clipping, and a
/// pause for breath is not a dead microphone.
@MainActor
@Observable
final class RecorderInputHealthMonitor {
    private(set) var health: RecorderInputHealth = .unknown

    /// `AudioMeter` reports **normalized 0…1**, not dBFS: `Recorder` maps −60…0 dB onto that range
    /// and then EMA-smooths it. Thresholds have to be expressed in the same units — an earlier dBFS
    /// version tripped clipping on every take, because any peak is trivially above −1.5.
    ///
    /// Calibrated against the EMA smoothing (0.6 old / 0.4 new), which pulls sustained peaks well
    /// below their instantaneous value — 0.96 was effectively unreachable and never fired.
    /// 0.90 ≈ −6 dB (genuinely hot), 0.16 ≈ −50 dB (barely above the noise floor).
    private let clipThreshold: Double = 0.90
    private let quietThreshold: Double = 0.16
    private let sustainedSampleCount = 12  // ~1.2s at the 10Hz sample rate below

    private var clipRun = 0
    private var quietRun = 0
    private var sawAnySignal = false

    func reset() {
        health = .unknown
        clipRun = 0
        quietRun = 0
        sawAnySignal = false
    }

    func ingest(_ meter: AudioMeter) {
        if meter.peakPower >= clipThreshold {
            clipRun += 1
        } else {
            clipRun = 0
        }

        if meter.averagePower <= quietThreshold {
            quietRun += 1
        } else {
            quietRun = 0
            sawAnySignal = true
        }

        if clipRun >= sustainedSampleCount {
            health = .clipping
        } else if quietRun >= sustainedSampleCount {
            health = .quiet
        } else if sawAnySignal {
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

    /// A healthy take with nothing attached earns no space. Degradation does.
    static func shouldRender(
        health: RecorderInputHealth,
        context: RecorderContextSummary
    ) -> Bool {
        health.isProblem || !context.isEmpty
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
        if let label = health.label {
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
