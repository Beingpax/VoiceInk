import Foundation
import SwiftUI

/// Ends a take that has gone quiet, after warning first.
///
/// The failure this exists for is walking away with the recorder running — a take that quietly
/// accumulates minutes of room tone and then goes to a paid transcription API.
///
/// It warns before acting, and any sound at all cancels the countdown, because stopping someone
/// mid-thought while they pause to think is far worse than the problem being solved.
@MainActor
@Observable
final class RecorderSilenceWatch {
    /// Seconds of continuous silence before the countdown starts.
    private let silenceGrace: TimeInterval = 8
    /// Countdown length once it has started.
    private let countdown: TimeInterval = 5

    private(set) var secondsRemaining: Int?

    private var silentSince: Date?

    var isCountingDown: Bool { secondsRemaining != nil }

    func reset() {
        silentSince = nil
        secondsRemaining = nil
    }

    /// - Returns: `true` when the take should be stopped now.
    func ingest(isSilent: Bool, now: Date = .now) -> Bool {
        guard isSilent else {
            // Any sound clears the whole thing — no partial credit, no lingering countdown.
            reset()
            return false
        }

        guard let silentSince else {
            self.silentSince = now
            return false
        }

        let elapsed = now.timeIntervalSince(silentSince)
        guard elapsed >= silenceGrace else {
            secondsRemaining = nil
            return false
        }

        let intoCountdown = elapsed - silenceGrace
        guard intoCountdown < countdown else {
            reset()
            return true
        }

        secondsRemaining = Int((countdown - intoCountdown).rounded(.up))
        return false
    }
}

/// The countdown, shown in the Signal Strip's health slot while it runs.
struct RecorderSilenceCountdown: View {
    let secondsRemaining: Int
    let onKeepRecording: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(
                String(
                    format: String(localized: "Silent — stopping in %lld"),
                    Int64(secondsRemaining)
                )
            )
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(AppTheme.Status.warningStrong)

            Button(action: onKeepRecording) {
                Text("Keep recording")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(AppTheme.Recorder.label)
                    .padding(.horizontal, 6)
                    .frame(height: 15)
                    .background(Capsule().fill(AppTheme.Recorder.controlFill))
            }
            .buttonStyle(.plain)
        }
    }
}
