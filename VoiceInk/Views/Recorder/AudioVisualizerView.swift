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

    @State private var heights: [CGFloat]

    init(audioMeter: AudioMeter, color: Color, isActive: Bool) {
        self.audioMeter = audioMeter
        self.color = color
        self.isActive = isActive

        // Create smooth wave phases
        self.phases = (0..<barCount).map { Double($0) * 0.4 }
        _heights = State(initialValue: Array(repeating: minHeight, count: barCount))
    }

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(color.opacity(0.85))
                    .frame(width: barWidth, height: heights[index])
            }
        }
        .onChange(of: audioMeter) { _, newValue in
            updateWave(level: isActive ? newValue.averagePower : 0)
        }
        .onChange(of: isActive) { _, active in
            if !active { resetWave() }
        }
    }

    private func updateWave(level: Double) {
        let time = Date().timeIntervalSince1970
        let amplitude = max(0, min(1, level))

        // Boost lower levels for better visibility
        let boosted = pow(amplitude, 0.7)

        withAnimation(.easeOut(duration: 0.08)) {
            for i in 0..<barCount {
                let wave = sin(time * 8 + phases[i]) * 0.5 + 0.5
                let centerDistance = abs(Double(i) - Double(barCount) / 2) / Double(barCount / 2)
                let centerBoost = 1.0 - (centerDistance * 0.4)

                let height = minHeight + CGFloat(boosted * wave * centerBoost) * (maxHeight - minHeight)
                heights[i] = max(minHeight, height)
            }
        }
    }

    private func resetWave() {
        withAnimation(.easeOut(duration: 0.2)) {
            heights = Array(repeating: minHeight, count: barCount)
        }
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
