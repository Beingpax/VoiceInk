import SwiftUI

/// The voice, drawn as light spreading out of the notch.
///
/// Border thickness alone is a poor carrier for a voice: it has one dimension and no memory, so a
/// steady tone and a sentence full of stresses look identical. A trace has both — you can see the
/// shape of what you just said, not merely how loud you are right now.
///
/// **Why it radiates from the centre rather than scrolling.** The obvious build is a left-to-right
/// oscilloscope, and it was wrong here for two reasons. Under a centred notch an asymmetric trace
/// looks like it slipped out of alignment, and a trace that runs off one edge has to be cut off
/// somewhere, which always reads as a clipped chart. Anchoring the newest sample at the centre and
/// pushing older ones outward in both directions fixes both at once: it is symmetric under the
/// cutout, and both ends taper to nothing on their own, so nothing is ever cut. Your voice appears
/// to be emitted by the notch and ripple away from it.
///
/// It is filled rather than stroked. An outlined waveform is a diagram; a filled one lit from its
/// own centre line is light, which is the only thing ambient mode is allowed to be made of.
struct AmbientVoiceTrace: View {
    /// Newest sample last, each 0…1.
    let samples: [Double]
    let tint: Color
    let intensity: Double

    /// Peak displacement either side of the centre line.
    private let peakAmplitude: CGFloat = 17
    /// Even in silence the shape keeps a sliver of height, so the trace reads as present and
    /// listening rather than as something that failed to draw.
    private let restingAmplitude: CGFloat = 0.045

    var body: some View {
        Canvas { context, size in
            guard samples.count > 2 else { return }

            let profile = self.profile(in: size)
            let body = filledPath(profile, in: size)

            // Three passes, in order of how far the light travels.

            // 1. Bloom — well outside the shape, this is what makes it a glow and not a graphic.
            var bloom = context
            bloom.addFilter(.blur(radius: 11))
            bloom.fill(body, with: .color(tint.opacity(0.30 * intensity)))

            // 2. Body — brightest along the centre line and falling off toward both edges, so the
            //    shape is lit from within rather than being a flat silhouette.
            var core = context
            core.addFilter(.blur(radius: 1.6))
            core.fill(
                body,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: tint.opacity(0.10 * intensity), location: 0.0),
                        .init(color: tint.opacity(0.85 * intensity), location: 0.5),
                        .init(color: tint.opacity(0.10 * intensity), location: 1.0),
                    ]),
                    startPoint: CGPoint(x: size.width / 2, y: 0),
                    endPoint: CGPoint(x: size.width / 2, y: size.height)
                )
            )

            // 3. Rim — a hairline on the upper and lower contours only. This is what lets you read
            //    individual syllables; without it loud passages merge into one bright mass.
            var rim = context
            rim.addFilter(.blur(radius: 0.5))
            let style = StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)
            rim.stroke(
                curve(through: profile.map { CGPoint(x: $0.x, y: $0.centreY - $0.amplitude) }),
                with: .color(tint.opacity(0.9 * intensity)),
                style: style
            )
            rim.stroke(
                curve(through: profile.map { CGPoint(x: $0.x, y: $0.centreY + $0.amplitude) }),
                with: .color(tint.opacity(0.9 * intensity)),
                style: style
            )
        }
        .allowsHitTesting(false)
    }

    // MARK: - Geometry

    private struct Column {
        let x: CGFloat
        let centreY: CGFloat
        let amplitude: CGFloat
    }

    /// One column per sample per side, newest in the middle.
    private func profile(in size: CGSize) -> [Column] {
        let count = samples.count
        let centreY = size.height / 2
        let half = size.width / 2
        let step = half / CGFloat(count - 1)

        return (-(count - 1)...(count - 1)).map { offset in
            // How far back in time this column is: 0 at the centre, oldest at both ends.
            let age = abs(offset)
            let u = CGFloat(age) / CGFloat(count - 1)

            // Meter values cluster low — normal speech averages around 0.45 — so a linear mapping
            // wastes most of the available height. The root curve lifts the range people
            // actually speak in without letting shouting run off the top.
            let raw = pow(max(samples[count - 1 - age], 0), 0.65)

            // Older columns fade toward nothing, which is what makes both ends resolve on their
            // own instead of being clipped.
            let falloff = pow(1 - u, 1.5)

            return Column(
                x: half + CGFloat(offset) * step,
                centreY: centreY,
                amplitude: (CGFloat(raw) * falloff + restingAmplitude * falloff) * peakAmplitude
            )
        }
    }

    /// Closed lens shape: the upper contour out, the lower contour back.
    private func filledPath(_ profile: [Column], in size: CGSize) -> Path {
        var path = curve(through: profile.map { CGPoint(x: $0.x, y: $0.centreY - $0.amplitude) })
        let lower = profile.reversed().map { CGPoint(x: $0.x, y: $0.centreY + $0.amplitude) }

        path.addLine(to: lower[0])
        appendCurve(to: &path, through: lower)
        path.closeSubpath()
        return path
    }

    /// Quadratic smoothing through midpoints. Raw samples at 30Hz produce a sawtooth; speech
    /// should look like a wave.
    private func curve(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        appendCurve(to: &path, through: points)
        return path
    }

    private func appendCurve(to path: inout Path, through points: [CGPoint]) {
        guard points.count > 2 else {
            points.dropFirst().forEach { path.addLine(to: $0) }
            return
        }
        for index in 1..<(points.count - 1) {
            let control = points[index]
            let next = points[index + 1]
            let midpoint = CGPoint(x: (control.x + next.x) / 2, y: (control.y + next.y) / 2)
            path.addQuadCurve(to: midpoint, control: control)
        }
        path.addLine(to: points[points.count - 1])
    }
}
