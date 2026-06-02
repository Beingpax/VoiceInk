import SwiftUI

// MARK: - Lightweight Wave Profile
private struct WaveProfile {
    let minHeight: CGFloat
    let maxHeight: CGFloat

    func amplitude(for audioPower: Double, isActive: Bool) -> CGFloat {
        let normalizedPower = max(0, min(1, audioPower))
        let energy = isActive ? CGFloat(pow(normalizedPower, 0.45) * 1.1) : 0.12
        return minHeight + (maxHeight - minHeight) * energy
    }
}

// MARK: - AudioVisualizer Component
struct AudioVisualizer: View {
    let audioMeter: AudioMeter
    let color: Color
    let isActive: Bool

    @AppStorage("visualizerWaveformHeight") private var visualizerWaveformHeight = 75.0
    @AppStorage("visualizerSpeed") private var visualizerSpeed = 1.0
    @AppStorage("visualizerLineTheme") private var visualizerLineTheme = "cyber"

    var body: some View {
        let height = CGFloat(visualizerWaveformHeight)
        let speed = visualizerSpeed
        let primary = Self.resolveColor(theme: visualizerLineTheme, primary: true)
        let secondary = Self.resolveColor(theme: visualizerLineTheme, primary: false)
        TimelineView(.animation(minimumInterval: 0.05)) { context in
            WaveCanvas(
                audioPower: audioMeter.averagePower,
                isActive: isActive,
                maxHeight: height,
                time: context.date.timeIntervalSinceReferenceDate,
                speed: speed,
                primaryColor: primary,
                secondaryColor: secondary
            )
        }
        .frame(maxWidth: .infinity, idealHeight: height, maxHeight: height)
    }

    static func resolveColor(theme: String, primary: Bool) -> Color {
        switch theme {
        case "sunset": return primary ? Color(red: 1.0, green: 0.3, blue: 0.3) : Color(red: 0.9, green: 0.0, blue: 0.6)
        case "matrix": return primary ? Color(red: 0.0, green: 1.0, blue: 0.53) : Color(red: 0.0, green: 0.8, blue: 0.2)
        case "aurora": return primary ? Color(red: 0.0, green: 0.95, blue: 1.0) : Color(red: 0.5, green: 0.0, blue: 1.0)
        case "mono": return primary ? .white : Color(red: 0.7, green: 0.7, blue: 0.7)
        default: return primary ? Color(red: 0.28, green: 0.58, blue: 0.95) : Color(red: 0.54, green: 0.12, blue: 0.92)
        }
    }
}

struct StaticVisualizer: View {
    let color: Color

    @AppStorage("visualizerWaveformHeight") private var visualizerWaveformHeight = 75.0

    var body: some View {
        let height = CGFloat(visualizerWaveformHeight)
        let primary = AudioVisualizer.resolveColor(theme: "cyber", primary: true)
        let secondary = AudioVisualizer.resolveColor(theme: "cyber", primary: false)
        WaveCanvas(
            audioPower: 0,
            isActive: false,
            maxHeight: height,
            time: 0,
            speed: 1.0,
            primaryColor: primary,
            secondaryColor: secondary
        )
        .frame(maxWidth: .infinity, idealHeight: height, maxHeight: height)
    }
}

// MARK: - Performant Wave Canvas (5 strands, 30 steps, 20fps, zero @AppStorage)
private struct WaveCanvas: View {
    let audioPower: Double
    let isActive: Bool
    let maxHeight: CGFloat
    let time: TimeInterval
    let speed: Double
    let primaryColor: Color
    let secondaryColor: Color

    private let strandsCount = 5
    private let stepsCount = 30

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }

            let midY = size.height / 2
            let scale = min(1, size.height / maxHeight)
            let sideInset: CGFloat = 8
            let usableWidth = size.width - sideInset * 2
            let stepX = usableWidth / CGFloat(stepsCount - 1)

            let profile = WaveProfile(minHeight: 8, maxHeight: maxHeight)
            let amp = profile.amplitude(for: audioPower, isActive: isActive) * scale
            let t = time * speed

            // Draw strands directly — no fill pass, no glow filter
            for s in 0..<strandsCount {
                let layer = Double(s)
                let spd = 1.2 + layer * 0.3
                let freq = 0.015 + layer * 0.002
                let phaseOffset = layer * 0.9
                let layerAmpScale: CGFloat = s == 0 ? 1.0 : (s == 1 ? 0.8 : 0.5 - CGFloat(s) * 0.05)

                var path = Path()
                var prevPoint = CGPoint.zero

                for i in 0..<stepsCount {
                    let x = sideInset + CGFloat(i) * stepX
                    let fraction = Double(i) / Double(stepsCount - 1)
                    let centered = fraction * 2.0 - 1.0
                    let envelope: CGFloat = CGFloat(1.0 - centered * centered)

                    let phase: Double = Double(x) * freq + t * spd + phaseOffset
                    let sinVal: CGFloat = CGFloat(sin(phase))
                    let y: CGFloat = midY + sinVal * amp * envelope * layerAmpScale

                    let point = CGPoint(x: x, y: y)
                    if i == 0 {
                        path.move(to: point)
                    } else {
                        let mid = CGPoint(x: (prevPoint.x + point.x) / 2, y: (prevPoint.y + point.y) / 2)
                        path.addQuadCurve(to: mid, control: prevPoint)
                    }
                    prevPoint = point
                }
                path.addLine(to: prevPoint)

                let isPrimary = s < 2
                let opacity = isActive ? (isPrimary ? 0.9 : 0.3) : (isPrimary ? 0.4 : 0.1)
                let lineWidth = (isPrimary ? 2.0 : 0.8) * scale
                let color = isPrimary ? primaryColor : secondaryColor

                context.stroke(path, with: .color(color.opacity(opacity)),
                             style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
        }
    }
}

// MARK: - Processing Status Display
struct ProcessingStatusDisplay: View {
    enum Mode {
        case transcribing
        case enhancing
    }

    let mode: Mode
    let color: Color

    var body: some View {
        WaveformLoaderView(color: color, mode: mode)
            .frame(height: 45)
    }
}

struct WaveformLoaderView: View {
    let color: Color
    var mode: ProcessingStatusDisplay.Mode = .transcribing
    @State private var isAnimating = false

    private var resolvedColor: Color {
        mode == .enhancing ? Color(red: 1.0, green: 0.416, blue: 0.0) : Color(red: 0.54, green: 0.12, blue: 0.92)
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(resolvedColor)
                    .frame(width: 3, height: isAnimating ? heights[index] : 6)
                    .animation(
                        .easeInOut(duration: 0.5 + Double(index) * 0.08)
                        .repeatForever(autoreverses: true),
                        value: isAnimating
                    )
            }
        }
        .frame(height: 35)
        .onAppear { isAnimating = true }
    }

    private let heights: [CGFloat] = [18, 30, 24, 32, 14]
}
