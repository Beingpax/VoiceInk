import SwiftUI

/// The voice, drawn as light along the edge it is already lighting.
///
/// Border thickness alone is a poor carrier for a voice: it has one dimension and no memory, so a
/// steady tone and a sentence full of stresses look identical. A trace has both — you can see the
/// shape of what you just said, not merely how loud you are right now.
///
/// On a notched Mac this hangs off the cutout's straight bottom edge, which is the one place the
/// hardware already draws a line for us. Elsewhere it sits under the top edge of the display.
struct AmbientVoiceTrace: View {
    /// Newest sample last, each 0…1.
    let samples: [Double]
    let tint: Color
    let intensity: Double

    /// Peak displacement either side of the centre line.
    private let amplitude: CGFloat = 11

    var body: some View {
        Canvas { context, size in
            guard samples.count > 1 else { return }

            let path = tracePath(in: size)

            // Wide, soft pass first — this is what makes it read as emitted light rather than a
            // drawn line. The crisp pass on top gives it definition.
            context.addFilter(.blur(radius: 5))
            context.stroke(
                path,
                with: .color(tint.opacity(0.55 * intensity)),
                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
            )

            var sharp = context
            sharp.addFilter(.blur(radius: 0.6))
            sharp.stroke(
                path,
                with: .color(tint.opacity(0.95 * intensity)),
                style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
            )
        }
        .allowsHitTesting(false)
    }

    /// A mirrored trace around the centre line, smoothed with quadratic segments so speech reads as
    /// a waveform rather than a sawtooth of 30Hz samples.
    private func tracePath(in size: CGSize) -> Path {
        var path = Path()
        let midY = size.height / 2
        let step = size.width / CGFloat(max(samples.count - 1, 1))

        // Older samples fade toward the leading edge, so the trace appears to stream out of the
        // left rather than being clipped by it.
        func point(at index: Int) -> CGPoint {
            let fade = CGFloat(index) / CGFloat(max(samples.count - 1, 1))
            let value = CGFloat(samples[index]) * fade
            return CGPoint(x: CGFloat(index) * step, y: midY - value * amplitude)
        }

        path.move(to: point(at: 0))
        for index in 1..<samples.count {
            let current = point(at: index)
            let previous = point(at: index - 1)
            let control = CGPoint(x: (previous.x + current.x) / 2, y: previous.y)
            path.addQuadCurve(to: current, control: control)
        }

        // Mirror back along the bottom to close the shape symmetrically.
        for index in stride(from: samples.count - 1, through: 0, by: -1) {
            let fade = CGFloat(index) / CGFloat(max(samples.count - 1, 1))
            let value = CGFloat(samples[index]) * fade
            let current = CGPoint(x: CGFloat(index) * step, y: midY + value * amplitude)
            path.addLine(to: current)
        }

        return path
    }
}
