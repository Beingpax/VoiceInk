import SwiftUI

/// Reduces a whole take to a fixed number of buckets, for replaying it as light while it is being
/// transcribed.
enum AmbientTakeEnvelope {
    /// - Note: buckets take the **peak** of their range, not the mean. Averaging a minute of speech
    ///   flattens it into a smooth mound that no longer looks like anything was said.
    static func downsample(_ samples: [Double], to buckets: Int) -> [Double] {
        guard buckets > 0 else { return [] }
        guard samples.count > buckets else { return samples }

        let stride = Double(samples.count) / Double(buckets)
        return (0..<buckets).map { index in
            let lower = Int(Double(index) * stride)
            let upper = min(Int(Double(index + 1) * stride), samples.count)
            guard upper > lower else { return samples[min(lower, samples.count - 1)] }
            return samples[lower..<upper].max() ?? 0
        }
    }
}

/// The voice, drawn as the top edge of the ambient light rather than as an object underneath it.
///
/// An earlier version was a separate lens floating below the notch. It modulated well but read as a
/// widget parked on the wallpaper: its own bloom, its own silhouette, and a band of unlit screen
/// between it and the glow it was supposed to belong to. Two lights, not one.
///
/// This is the same waveform folded into the frame. The band hangs off the display's actual top
/// edge — tracing the notch silhouette across the middle and stepping out to the flat bezel at the
/// cutout's walls — and its lower contour is the waveform. Where the voice does not reach, the band
/// settles to the depth of the side-edge wash, so the top flows into the corners and down the sides
/// without a seam.
///
/// Newest sample at the centre, older pushed outward both ways, so under a centred cutout the voice
/// appears to be emitted by the hardware and ripple away from it.
struct AmbientVoiceCrest: View {
    /// While listening: newest sample last. While processing: the take from start to end.
    let samples: [Double]
    /// The contour colour — the measured, legible one.
    let tint: Color
    /// The body colour. Equal to `tint` on dark grounds; vivid inside a deep rim on light ones.
    var core: Color?
    let intensity: Double
    /// On a light background the weighting flips: less spread, more edge. Bloom over white is haze.
    var palette = AmbientPalette(isLight: false)

    /// Height of the hardware cutout, or 0 on a display without one. The band's upper boundary
    /// traces this, so the light appears to be cast by the bezel itself.
    let notchDrop: CGFloat
    let notchWidth: CGFloat

    /// Depth of the band where the voice does not reach. Matched to the side-edge wash so the two
    /// meet at the corners at the same thickness — this is what makes it one light and not two.
    let baseDepth: CGFloat
    /// Additional depth at full voice, at the centre.
    let peakDepth: CGFloat

    /// Non-nil while transcribing. The crest stops being a live meter and becomes the take being
    /// read back: the whole waveform is laid out from the notch outward, and the finished portion
    /// is lit while the remainder waits in outline. Progress becomes distance travelled along your
    /// own recording rather than an abstract bar.
    var progress: Double?

    /// How far past the cutout the silhouette returns to the flat bezel. Short on purpose: the
    /// notch has near-vertical walls, and easing over any real distance left an unlit wedge beside
    /// the cutout where the band had already climbed away from the glass.
    private let wall: CGFloat = 14
    /// Horizontal reach of the live voice. Wide enough that speaking lights a good sweep of the top
    /// edge rather than only the notch, which is what ties the crest to the corners.
    private let spread: CGFloat = 1.7
    /// Sampling step along the width. Fine enough to resolve the cutout wall, coarse enough that a
    /// wide display is not thousands of path segments per frame.
    private let step: CGFloat = 3

    private var isReplaying: Bool { progress != nil }

    var body: some View {
        Canvas { context, size in
            let upper = boundary(in: size, includeVoice: false)
            let lower = boundary(in: size, includeVoice: true)
            guard upper.count > 1 else { return }

            var band = curve(through: upper)
            band.addLine(to: lower[lower.count - 1])
            appendCurve(to: &band, through: lower.reversed())
            band.closeSubpath()

            let contour = curve(through: lower)
            let deepest = lower.map(\.y).max() ?? size.height

            // A tight shadow under the contour, so on a light ground the edge sits above the page
            // rather than staining it. Drawn once — paint() runs twice while replaying, and a
            // stacked shadow made the finished half of the take visibly murkier than the rest.
            if palette.contourShadow > 0 {
                var shade = context
                shade.addFilter(.blur(radius: 6))
                shade.translateBy(x: 0, y: 2)
                shade.stroke(
                    contour,
                    with: .color(.black.opacity(palette.contourShadow * intensity)),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                )
            }

            guard let progress else {
                paint(band, contour: contour, into: context, deepest: deepest, size: size, scale: 1)
                return
            }

            // Everything still to be processed, in outline — so the remaining work is visible as
            // distance rather than implied.
            paint(band, contour: contour, into: context, deepest: deepest, size: size, scale: 0.2)

            let half = size.width / 2
            let reach = max(CGFloat(progress), 0.004) * half
            var lit = context
            lit.clip(
                to: Path(CGRect(x: half - reach, y: 0, width: reach * 2, height: size.height)))
            paint(band, contour: contour, into: lit, deepest: deepest, size: size, scale: 1)

            playheads(at: reach, into: context, size: size, deepest: deepest)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Painting

    /// Three passes, ordered by how far the light travels.
    private func paint(
        _ band: Path,
        contour: Path,
        into context: GraphicsContext,
        deepest: CGFloat,
        size: CGSize,
        scale: Double
    ) {
        let alpha = intensity * scale

        // 1. Bloom, well outside the band. This is the layer that overlaps the edge wash and the
        //    notch halo, so the three read as one light source rather than three.
        var bloom = context
        let body = core ?? tint
        bloom.addFilter(.blur(radius: 18 * palette.crestBlurScale))
        bloom.fill(band, with: .color(body.opacity(palette.haloAlpha * alpha)))

        // 2. Body — brightest against the bezel and falling away downward, the same direction the
        //    frame's own wash falls. Light seeping in, not a shape sitting on the screen.
        _ = 0
        var fill = context
        fill.addFilter(.blur(radius: 2.5 * palette.crestBlurScale))
        fill.fill(
            band,
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: body.opacity(palette.coreAlphaTop * alpha), location: 0.0),
                    .init(color: body.opacity(palette.coreAlphaMid * alpha), location: 0.55),
                    .init(color: body.opacity(0), location: 1.0),
                ]),
                startPoint: CGPoint(x: size.width / 2, y: 0),
                endPoint: CGPoint(x: size.width / 2, y: deepest)
            )
        )

        // 3. A hairline on the lower contour only — the upper one is the hardware edge, which the
        //    notch halo already draws. Without this, loud passages merge into one bright mass and
        //    individual syllables stop being readable.
        var rim = context
        rim.addFilter(.blur(radius: 0.7 * palette.blurScale))
        rim.stroke(
            contour,
            with: .color(tint.opacity(min(palette.rimAlpha * alpha, 1))),
            style: StrokeStyle(
                lineWidth: 1.2 * palette.rimScale, lineCap: .round, lineJoin: .round)
        )
    }

    /// The two points where lit meets unlit, travelling outward from the notch as work completes.
    private func playheads(
        at reach: CGFloat, into context: GraphicsContext, size: CGSize, deepest: CGFloat
    ) {
        let half = size.width / 2
        for x in [half - reach, half + reach] {
            let top = hardwareEdge(at: x, width: size.width)
            let head = Path(
                roundedRect: CGRect(x: x - 1.2, y: top, width: 2.4, height: deepest - top),
                cornerRadius: 1.2
            )

            var glow = context
            glow.addFilter(.blur(radius: 7))
            glow.fill(head, with: .color(tint.opacity(0.85 * intensity)))
            context.fill(head, with: .color(tint.opacity(0.95 * intensity)))
        }
    }

    // MARK: - Geometry

    /// The display's physical top edge at `x`: the cutout's depth across the middle, returning to
    /// the flat bezel over the width of the cutout's own wall.
    private func hardwareEdge(at x: CGFloat, width: CGFloat) -> CGFloat {
        guard notchDrop > 0 else { return 0 }

        let distance = abs(x - width / 2)
        let halfNotch = notchWidth / 2
        if distance <= halfNotch { return notchDrop }

        let t = min((distance - halfNotch) / wall, 1)
        // Smoothstep, so the light turns the cutout's corner instead of creasing at it.
        return notchDrop * (1 - t * t * (3 - 2 * t))
    }

    /// How much voice reaches `x`, 0…1.
    private func voice(at x: CGFloat, width: CGFloat) -> CGFloat {
        guard samples.count > 2 else { return 0 }

        let u = min(abs(x - width / 2) / (width / 2), 1)
        let last = samples.count - 1

        let raw: Double
        let envelope: Double
        if isReplaying {
            // Distance from the notch is position within the take, so it unrolls outward.
            raw = pow(max(samples[min(Int(u * Double(last)), last)], 0), 0.65)
            envelope = edgeFade(u)
        } else {
            // Distance from the notch is age, so the newest audio sits under the cutout.
            raw = pow(max(samples[last - Int((u * CGFloat(last)).rounded())], 0), 0.65)
            // Gaussian reach rather than a hard cutoff: the voice has to arrive at the corners as
            // nothing at all, or the band would step down where it ends.
            envelope = exp(-pow(u * Double(spread), 2))
        }

        return CGFloat(raw) * CGFloat(envelope)
    }

    /// Holds full height until close to the corners, then resolves. Used only when replaying, where
    /// every part of the take deserves the same height regardless of where it landed.
    private func edgeFade(_ u: Double) -> Double {
        guard u > 0.88 else { return 1 }
        let t = (u - 0.88) / 0.12
        return 1 - t * t * (3 - 2 * t)
    }

    private func boundary(in size: CGSize, includeVoice: Bool) -> [CGPoint] {
        Swift.stride(from: 0, through: size.width, by: step).map { x in
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
