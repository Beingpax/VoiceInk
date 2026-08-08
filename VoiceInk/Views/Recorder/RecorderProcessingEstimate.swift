import Foundation
import SwiftUI

/// Predicts how long processing will take, from how long this model has taken before.
///
/// `ModelPerformanceSummary` has been recording `averageSpeedFactor` and
/// `averageProcessingDuration` per model all along and nothing used them. A 40-second take on a
/// model that historically runs at 3× realtime is done in roughly 13 seconds — worth saying,
/// rather than showing an indeterminate spinner for both transcription and enhancement as though
/// they were the same wait.
@MainActor
@Observable
final class RecorderProcessingEstimate {
    /// Fraction of the predicted wait elapsed, 0...1.
    private(set) var progress: Double = 0
    private(set) var remaining: TimeInterval?
    /// Model the estimate came from, shown as provenance so the number is not mysterious.
    private(set) var basis: String?

    private var startedAt: Date?
    private var expectedDuration: TimeInterval?

    /// Below this many past sessions the average is too noisy to promise anything.
    private static let minimumSessionsForEstimate = 3

    var hasEstimate: Bool { expectedDuration != nil }

    func begin(audioDuration: TimeInterval, modelName: String?) {
        startedAt = .now
        progress = 0
        remaining = nil
        expectedDuration = nil
        basis = nil

        guard let modelName,
            let performance = Self.performance(for: modelName),
            performance.sessionCount >= Self.minimumSessionsForEstimate
        else { return }

        if let speedFactor = performance.averageSpeedFactor, speedFactor > 0, audioDuration > 0 {
            expectedDuration = audioDuration / speedFactor
            basis = String(
                format: String(localized: "%@ · %.1f× realtime"),
                modelName, speedFactor
            )
        } else if let average = performance.averageProcessingDuration, average > 0 {
            expectedDuration = average
            basis = String(
                format: String(localized: "%@ · usually %@"),
                modelName, average.formatTiming()
            )
        }
    }

    func end() {
        startedAt = nil
        expectedDuration = nil
        remaining = nil
        progress = 0
        basis = nil
    }

    /// Called from the panel's existing sample loop.
    func tick() {
        guard let startedAt, let expectedDuration, expectedDuration > 0 else { return }

        let elapsed = Date().timeIntervalSince(startedAt)
        // Cap just short of complete: a bar that sits at 100% while still working reads as stuck.
        progress = min(elapsed / expectedDuration, 0.97)
        remaining = max(expectedDuration - elapsed, 0)
    }

    private static func performance(for modelName: String) -> ModelPerformanceSummary? {
        DashboardStatsCache.shared.currentSummary()?
            .modelPerformance(for: .allTime)
            .first { $0.kind == .transcription && $0.name == modelName }
    }
}

/// Progress and predicted remaining time, replacing an indeterminate spinner.
struct RecorderProcessingRow: View {
    let state: RecordingState
    let estimate: RecorderProcessingEstimate

    private var title: LocalizedStringKey {
        state == .enhancing ? "Enhancing" : "Transcribing"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.Recorder.labelSecondary)

                Spacer(minLength: 4)

                if let remaining = estimate.remaining, remaining > 0.5 {
                    Text(String(format: String(localized: "~%@ left"), remaining.formatTiming()))
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.Recorder.labelTertiary)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.Recorder.controlFill)
                    Capsule()
                        .fill(AppTheme.Status.warningStrong)
                        .frame(width: max(3, geo.size.width * estimate.progress))
                }
            }
            .frame(height: 3)

            if let basis = estimate.basis {
                Text(basis)
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.Recorder.labelTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
