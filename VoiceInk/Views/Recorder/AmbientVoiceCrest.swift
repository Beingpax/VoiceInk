import SwiftUI

/// The voice, drawn as the top edge of the ambient light rather than as an object underneath it.
///
/// The previous version was a separate lens floating below the notch. It modulated well but it read
/// as a widget someone had parked on the wallpaper: it had its own bloom, its own silhouette, and a
/// band of unlit screen between it and the glow it was supposed to belong to. Two lights, not one.
///
/// This is the same waveform folded into the frame. The band hangs off the display's actual top
/// edge — following the notch silhouette across the middle and easing out to the flat bezel at the
/// shoulders — and its lower contour is the waveform. Where the voice does not reach, the band
/// settles to exactly the depth of the side-edge wash, so the top edge flows into the corners and
/// down the sides without a seam. Speaking makes the light bulge downward out of the notch and
/// spread along the bezel; silence lets it settle back into being the frame.
///
/// The grammar from the previous version survives, because it was the part that worked: newest
/// sample at the centre, older samples pushed outward in both directions. Under a centred cutout
/// that reads as the light being emitted by the hardware and rippling away from it.
struct AmbientVoiceCrest: View {
    /// Newest sample last, each 0…1.
    let samples: [Double]
    let tint: Color
    let intensity: Double

    /// Height of the hardware cutout, or 0 on a display without one. The band's upper boundary
    /// traces this, so the light appears to be cast by the bezel itself.
    let notchDrop: CGFloat
    let notchWidth: CGFloat

    /// Depth of the band where the voice does not reach. Matched to the side-edge wash so the two
    /// meet at the corners at the same thickness — this is what makes it one light and not two.
    let baseDepth: CGFloat
    /// Additional depth at full voice, at the centre.
    let peakDepth: CGFloat

    /// How far past the cutout the notch silhouette eases back to the flat bezel.
    private let shoulder: CGFloat = 130
    /// Horizontal reach of the voice. Wide enough that speaking lights a good sweep of the top
    /// edge rather than only the notch, which is what ties the crest to the corners.
    private let spread: CGFloat = 1.7
    /// Sampling step along the width. Fine enough for the shoulder curve, coarse enough that a
    /// wide display is not thousands of path segments per frame.
    private let step: CGFloat = 4

    var body: some View {
        Canvas { context, size in
            let upper = boundary(in: size, includeVoice: false)
            let lower = boundary(in: size, includeVoice: true)
            guard upper.count > 1 else { return }

            var band = curve(through: upper)
            band.addLine(to: lower[lower.count - 1])
            appendCurve(to: &band, through: lower.reversed())
            band.closeSubpath()

            let deepest = lower.map(\.y).max() ?? size.height

            // 1. Bloom, well outside the band. This is the layer that overlaps the edge wash and
            //    the notch halo, so the three read as one light source rather than three.
            var bloom = context
            bloom.addFilter(.blur(radius: 18))
            bloom.fill(band, with: .color(tint.opacity(0.34 * intensity)))

            // 2. Body — brightest against the bezel and falling away downward, the same direction
            //    the frame's own wash falls. Light seeping in, not a shape sitting on the screen.
            var core = context
            core.addFilter(.blur(radius: 2.5))
            core.fill(
                band,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: tint.opacity(0.80 * intensity), location: 0.0),
                        .init(color: tint.opacity(0.34 * intensity), location: 0.55),
                        .init(color: tint.opacity(0.0), location: 1.0),
                    ]),
                    startPoint: CGPoint(x: size.width / 2, y: 0),
                    endPoint: CGPoint(x: size.width / 2, y: deepest)
                )
            )

            // 3. A hairline on the lower contour only — the upper one is the hardware edge and the
            //    notch halo already draws it. Without this, loud passages merge into one bright
            //    mass and you cannot read individual syllables.
            var rim = context
            rim.addFilter(.blur(radius: 0.7))
            rim.stroke(
                curve(through: lower),
                with: .color(tint.opacity(0.75 * intensity)),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
            )
        }
        .allowsHitTesting(false)
    }

    // MARK: - Geometry

    /// The display's physical top edge at `x`: the cutout's depth across the middle, easing back to
    /// the flat bezel over the shoulders.
    private func hardwareEdge(at x: CGFloat, width: CGFloat) -> CGFloat {
        guard notchDrop > 0 else { return 0 }

        let distance = abs(x - width / 2)
        let halfNotch = notchWidth / 2
        if distance <= halfNotch { return notchDrop }

        let t = min((distance - halfNotch) / shoulder, 1)
        // Smoothstep, so the light leaves the cutout without a visible crease.
        return notchDrop * (1 - t * t * (3 - 2 * t))
    }

    /// How much voice reaches `x`, 0…1.
    private func voice(at x: CGFloat, width: CGFloat) -> CGFloat {
        guard samples.count > 2 else { return 0 }

        let u = min(abs(x - width / 2) / (width / 2), 1)

        // Age maps to distance from centre, so the newest sample sits under the notch.
        let age = Int((u * CGFloat(samples.count - 1)).rounded())
        // Meter values cluster low — normal speech averages around 0.45 — so a linear mapping
        // wastes most of the available depth.
        let raw = pow(max(samples[samples.count - 1 - age], 0), 0.65)

        // Gaussian reach rather than a hard cutoff: the voice has to arrive at the corners as
        // nothing at all, or the band would step down where it ends.
        let envelope = exp(-pow(u * spread, 2))
        return CGFloat(raw) * CGFloat(envelope)
    }

    private func boundary(in size: CGSize, includeVoice: Bool) -> [CGPoint] {
        stride(from: 0, through: size.width, by: step).map { x in
            var y = hardwareEdge(at: x, width: size.width)
            if includeVoice {
                y += baseDepth + peakDepth * voice(at: x, width: size.width)
            }
            return CGPoint(x: x, y: y)
        }
    }

    /// Quadratic smoothing through midpoints. Raw samples at 30Hz produce a sawtooth; speech should
    /// look like a wave.
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
