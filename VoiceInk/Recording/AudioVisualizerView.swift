import SwiftUI

struct AudioVisualizer: View {
    let audioMeter: AudioMeter
    let color: Color
    let isActive: Bool

    private let barCount = 15
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2
    private let minHeight: CGFloat = 4
    private let maxHeight: CGFloat = 28

    private let phases: [Double]

    init(audioMeter: AudioMeter, color: Color, isActive: Bool) {
        self.audioMeter = audioMeter
        self.color = color
        self.isActive = isActive

        // Create smooth wave phases
        self.phases = (0..<barCount).map { Double($0) * 0.4 }
    }

    var body: some View {
        // TimelineView with 60Hz updates (native approach recommended by Apple WWDC 2021+)
        TimelineView(.animation(minimumInterval: 0.016)) { context in
            HStack(spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(color.opacity(0.85))
                        .frame(width: barWidth, height: calculateHeight(for: index, at: context.date))
                }
            }
        }
    }

    private func calculateHeight(for index: Int, at date: Date) -> CGFloat {
        guard isActive else { return minHeight }

        let time = date.timeIntervalSince1970
        let level = audioMeter.averagePower
        let amplitude = max(0, min(1, level))

        // Boost lower levels for better visibility
        let boosted = pow(amplitude, 0.7)

        // Wave calculation
        let wave = sin(time * 8 + phases[index]) * 0.5 + 0.5
        let centerDistance = abs(Double(index) - Double(barCount) / 2) / Double(barCount / 2)
        let centerBoost = 1.0 - (centerDistance * 0.4)

        let height = minHeight + CGFloat(boosted * wave * centerBoost) * (maxHeight - minHeight)
        return max(minHeight, height)
    }
}

struct StaticVisualizer: View {
    // Match AudioVisualizer dimensions
    private let barCount = 15
    private let barWidth: CGFloat = 3
    private let staticHeight: CGFloat = 4
    private let barSpacing: CGFloat = 2
    let color: Color

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { _ in
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(color.opacity(0.5))
                    .frame(width: barWidth, height: staticHeight)
            }
        }
    }
}

// MARK: - Processing Status Display (Transcribing/Enhancing states)
struct ProcessingStatusDisplay: View {
    enum Mode {
        case transcribing
        case enhancing
    }

    let mode: Mode
    let color: Color

    private var label: String {
        switch mode {
        case .transcribing:
            return "Transcribing"
        case .enhancing:
            return "Enhancing"
        }
    }

    private var animationSpeed: Double {
        switch mode {
        case .transcribing:
            return 0.18
        case .enhancing:
            return 0.22
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .foregroundColor(color)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            ProgressAnimation(color: color, animationSpeed: animationSpeed)
        }
        .frame(height: 28) // Match AudioVisualizer maxHeight for no layout shift
    }
}
