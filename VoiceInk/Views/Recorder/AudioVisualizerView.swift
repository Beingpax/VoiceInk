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

    var body: some View {
        let height = CGFloat(visualizerWaveformHeight)
        TimelineView(.animation(minimumInterval: 0.033)) { context in
            WaveCanvas(
                audioPower: audioMeter.averagePower,
                isActive: isActive,
                maxHeight: height,
                time: context.date.timeIntervalSinceReferenceDate
            )
        }
        .frame(maxWidth: .infinity, idealHeight: height, maxHeight: height)
    }
}

struct StaticVisualizer: View {
    let color: Color

    @AppStorage("visualizerWaveformHeight") private var visualizerWaveformHeight = 75.0

    var body: some View {
        let height = CGFloat(visualizerWaveformHeight)
        TimelineView(.animation(minimumInterval: 0.066)) { context in
            WaveCanvas(
                audioPower: 0,
                isActive: false,
                maxHeight: height,
                time: context.date.timeIntervalSinceReferenceDate
            )
        }
        .frame(maxWidth: .infinity, idealHeight: height, maxHeight: height)
    }
}

// MARK: - Performant Wave Canvas (8 strands, 50 steps, sin-only, 30fps)
private struct WaveCanvas: View {
    let audioPower: Double
    let isActive: Bool
    let maxHeight: CGFloat
    let time: TimeInterval

    @AppStorage("visualizerSpeed") private var visualizerSpeed = 1.0
    @AppStorage("visualizerLineTheme") private var visualizerLineTheme = "cyber"

    // Strand count and resolution — tuned for visual density vs CPU cost
    private let strandsCount = 8
    private let stepsCount = 50

    private var primaryColors: [Color] {
        switch visualizerLineTheme {
        case "sunset":
            return [Color(red: 1.0, green: 0.3, blue: 0.3), Color(red: 1.0, green: 0.6, blue: 0.1), .white]
        case "matrix":
            return [Color(red: 0.0, green: 1.0, blue: 0.53), Color(red: 0.0, green: 0.66, blue: 0.42), .white]
        case "aurora":
            return [Color(red: 0.0, green: 0.95, blue: 1.0), Color(red: 0.31, green: 0.67, blue: 1.0), .white]
        case "mono":
            return [.white, Color(red: 0.88, green: 0.88, blue: 0.88), .white]
        default: // cyber
            return [Color(red: 0.28, green: 0.58, blue: 0.95), Color(red: 0.18, green: 0.62, blue: 0.92), .white]
        }
    }

    private var secondaryColors: [Color] {
        switch visualizerLineTheme {
        case "sunset":
            return [Color(red: 0.9, green: 0.0, blue: 0.6), Color(red: 1.0, green: 0.2, blue: 0.4)]
        case "matrix":
            return [Color(red: 0.0, green: 0.8, blue: 0.2), Color(red: 0.38, green: 0.94, blue: 1.0)]
        case "aurora":
            return [Color(red: 0.5, green: 0.0, blue: 1.0), Color(red: 0.0, green: 0.95, blue: 1.0)]
        case "mono":
            return [Color(red: 0.7, green: 0.7, blue: 0.7), Color(red: 0.4, green: 0.4, blue: 0.4)]
        default: // cyber
            return [Color(red: 0.54, green: 0.12, blue: 0.92), Color(red: 0.32, green: 0.02, blue: 0.78)]
        }
    }

    private var glowColor: Color {
        switch visualizerLineTheme {
        case "sunset": return Color(red: 1.0, green: 0.3, blue: 0.3)
        case "matrix": return Color(red: 0.0, green: 1.0, blue: 0.53)
        case "aurora": return Color(red: 0.0, green: 0.95, blue: 1.0)
        case "mono": return .white
        default: return Color(red: 0.54, green: 0.12, blue: 0.92)
        }
    }

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
            let t = time * visualizerSpeed

            // 1. Filled volume shape (top boundary to bottom boundary)
            var topBoundary = [CGPoint]()
            var bottomBoundary = [CGPoint]()
            topBoundary.reserveCapacity(stepsCount)
            bottomBoundary.reserveCapacity(stepsCount)

            for i in 0..<stepsCount {
                let x = sideInset + CGFloat(i) * stepX
                let fraction = CGFloat(i) / CGFloat(stepsCount - 1)
                let envelope = 0.25 + 0.75 * exp(-pow((fraction * 2 - 1) * 1.4, 2))

                // Compute extremes across strands at this x position
                var minYAtX = midY
                var maxYAtX = midY
                for s in 0..<strandsCount {
                    let layer = Double(s)
                    let speed = 1.2 + sin(layer * 0.5) * 0.6
                    let freq = 0.015 + cos(layer * 0.4) * 0.005
                    let phase = Double(x) * freq + t * speed + layer * 0.7
                    let secondary = sin(phase * 0.45 + t * 0.5) * 0.3
                    let y = midY + CGFloat(sin(phase) + secondary) * amp * envelope * (0.3 + 0.7 * CGFloat(sin(layer * 0.6)))
                    if y < minYAtX { minYAtX = y }
                    if y > maxYAtX { maxYAtX = y }
                }
                topBoundary.append(CGPoint(x: x, y: minYAtX))
                bottomBoundary.append(CGPoint(x: x, y: maxYAtX))
            }

            // Draw filled volume
            var fillPath = Path()
            fillPath.move(to: topBoundary[0])
            for i in 1..<stepsCount {
                let prev = topBoundary[i - 1]
                let curr = topBoundary[i]
                let mid = CGPoint(x: (prev.x + curr.x) / 2, y: (prev.y + curr.y) / 2)
                fillPath.addQuadCurve(to: mid, control: prev)
            }
            fillPath.addLine(to: topBoundary[stepsCount - 1])
            for i in stride(from: stepsCount - 1, through: 0, by: -1) {
                fillPath.addLine(to: bottomBoundary[i])
            }
            fillPath.closeSubpath()

            context.fill(fillPath, with: .linearGradient(
                Gradient(colors: [
                    glowColor.opacity(isActive ? 0.12 : 0.04),
                    primaryColors[0].opacity(isActive ? 0.08 : 0.03),
                    secondaryColors[0].opacity(isActive ? 0.10 : 0.03)
                ]),
                startPoint: CGPoint(x: 0, y: midY),
                endPoint: CGPoint(x: size.width, y: midY)
            ))

            // 2. Draw individual strands
            for s in 0..<strandsCount {
                let layer = Double(s)
                let speed = 1.2 + sin(layer * 0.5) * 0.6
                let freq = 0.015 + cos(layer * 0.4) * 0.005
                let phaseOffset = layer * 0.7
                let layerAmpScale = 0.3 + 0.7 * CGFloat(sin(layer * 0.6))

                var path = Path()
                var prevPoint = CGPoint.zero

                for i in 0..<stepsCount {
                    let x = sideInset + CGFloat(i) * stepX
                    let fraction = CGFloat(i) / CGFloat(stepsCount - 1)
                    let envelope = 0.25 + 0.75 * exp(-pow((fraction * 2 - 1) * 1.4, 2))

                    let phase = Double(x) * freq + t * speed + phaseOffset
                    let secondary = sin(phase * 0.45 + t * 0.5) * 0.3
                    let y = midY + CGFloat(sin(phase) + secondary) * amp * envelope * layerAmpScale

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

                // Style: primary strands get gradient + glow, others are subtle
                let isPrimary = (s == 2 || s == 5)
                let isSecondary = s.isMultiple(of: 2) && !isPrimary

                if isPrimary {
                    var glowCtx = context
                    glowCtx.addFilter(.shadow(
                        color: glowColor.opacity(isActive ? 0.6 : 0.2),
                        radius: isActive ? 6 : 2, x: 0, y: 0
                    ))
                    glowCtx.stroke(path, with: .linearGradient(
                        Gradient(colors: primaryColors),
                        startPoint: CGPoint(x: 0, y: midY),
                        endPoint: CGPoint(x: size.width, y: midY)
                    ), style: StrokeStyle(lineWidth: (isActive ? 2.0 : 1.0) * scale, lineCap: .round))
                } else if isSecondary {
                    context.stroke(path, with: .linearGradient(
                        Gradient(colors: secondaryColors),
                        startPoint: CGPoint(x: 0, y: midY),
                        endPoint: CGPoint(x: size.width, y: midY)
                    ), style: StrokeStyle(lineWidth: (isActive ? 1.2 : 0.6) * scale, lineCap: .round))
                } else {
                    context.stroke(path, with: .color(
                        glowColor.opacity(isActive ? 0.2 : 0.08)
                    ), style: StrokeStyle(lineWidth: 0.5 * scale, lineCap: .round))
                }
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
    @AppStorage("visualizerParticleColor") private var visualizerParticleColor = "orange"

    let color: Color
    var mode: ProcessingStatusDisplay.Mode = .transcribing
    @State private var isAnimating = false

    private var resolvedColor: Color {
        let base = visualizerParticleColor.lowercased()
        if base == "orange" {
            return Color(red: 1.0, green: 0.416, blue: 0.0)
        } else if base == "purple" {
            return Color(red: 0.54, green: 0.12, blue: 0.92)
        } else if base == "indigo" {
            return Color(red: 0.42, green: 0.38, blue: 0.98)
        } else {
            return mode == .enhancing ? Color(red: 1.0, green: 0.416, blue: 0.0) : Color(red: 0.54, green: 0.12, blue: 0.92)
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<9) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(resolvedColor)
                    .frame(width: 3, height: getHeight(for: index))
                    .animation(
                        .easeInOut(duration: getDuration(for: index))
                        .repeatForever(autoreverses: true)
                        .delay(getDelay(for: index)),
                        value: isAnimating
                    )
            }
        }
        .frame(height: 35)
        .onAppear {
            isAnimating = true
        }
    }

    private func getHeight(for index: Int) -> CGFloat {
        if !isAnimating {
            return 6
        }
        let heights: [CGFloat] = [12, 28, 18, 35, 20, 32, 14, 24, 8]
        return heights[index % heights.count]
    }

    private func getDuration(for index: Int) -> Double {
        let durations = [0.4, 0.55, 0.45, 0.6, 0.5, 0.65, 0.42, 0.58, 0.38]
        return durations[index % durations.count]
    }

    private func getDelay(for index: Int) -> Double {
        let delays = [0.0, 0.1, 0.2, 0.05, 0.15, 0.25, 0.08, 0.12, 0.02]
        return delays[index % delays.count]
    }
}
