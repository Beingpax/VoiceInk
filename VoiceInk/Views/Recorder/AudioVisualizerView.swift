import SwiftUI

// MARK: - Seeded Noise (Deterministic Hash-Based Value Noise / FBM)
struct WaveNoise {
    static let permutation: [Int] = {
        var arr = Array(0...255)
        // Hardcoded shuffled array to guarantee identical seed and avoid runtime generation
        let fixed = [
            151,160,137,91,90,15,131,13,201,95,96,53,194,233,7,225,140,36,103,30,69,142,8,99,37,240,21,10,23,
            190, 6,148,247,120,234,75,0,26,197,62,94,252,219,203,117,35,11,32,57,177,33,88,237,149,56,87,174,
            20,125,136,171,168, 68,175,74,165,71,134,139,48,27,166,77,146,158,231,83,111,229,122,60,211,133,
            230,220,105,92,41,55,46,245,40,244,102,143,54, 65,25,63,161, 1,216,80,73,209,76,132,187,208, 89,
            18,169,200,196,135,130,116,188,159,86,164,100,109,198,173,186, 3,64,52,217,226,250,124,123,5,202,
            38,147,118,126,255,82,85,212,207,206,59,227,47,16,58,17,182,189,28,42,223,183,170,213,119,248,152,
            2,44,154,163, 70,221,153,101,155,167, 43,172,9,129,22,39,253, 19,98,108,110,79,113,224,232,178,185,
            112,104,218,246,97,228,251,34,242,193,238,210,144,12,191,179,162,241, 81,51,145,235,249,14,239,107,
            49,192,214, 31,181,199,106,157,184, 84,204,176,115,121,50,45,127, 4,150,254,138,236,205,93,222,114,
            67,29,24,72,243,141,128,195,78,66,215,61,156,180
        ]
        return fixed + fixed
    }()

    static func noise1D(_ x: Double) -> Double {
        let xInt = Int(floor(x)) & 255
        let xFrac = x - floor(x)
        let t = fade(xFrac)
        
        let g0 = grad(permutation[xInt], xFrac)
        let g1 = grad(permutation[xInt + 1], xFrac - 1)
        
        return lerp(g0, g1, t)
    }

    static func noise2D(_ x: Double, _ y: Double) -> Double {
        let X = Int(floor(x)) & 255
        let Y = Int(floor(y)) & 255
        
        let xf = x - floor(x)
        let yf = y - floor(y)
        
        let u = fade(xf)
        let v = fade(yf)
        
        let aa = permutation[permutation[X] + Y]
        let ab = permutation[permutation[X] + Y + 1]
        let ba = permutation[permutation[X + 1] + Y]
        let bb = permutation[permutation[X + 1] + Y + 1]
        
        let x1 = lerp(grad2D(aa, xf, yf), grad2D(ba, xf - 1, yf), u)
        let x2 = lerp(grad2D(ab, xf, yf - 1), grad2D(bb, xf - 1, yf - 1), u)
        
        return lerp(x1, x2, v)
    }

    static func fbm2D(_ x: Double, _ y: Double, octaves: Int = 3) -> Double {
        var value = 0.0
        var amplitude = 0.5
        var frequency = 1.0
        for _ in 0..<octaves {
            value += amplitude * noise2D(x * frequency, y * frequency)
            amplitude *= 0.5
            frequency *= 2.0
        }
        return value
    }

    private static func fade(_ t: Double) -> Double {
        return t * t * t * (t * (t * 6 - 15) + 10)
    }

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        return a + t * (b - a)
    }

    private static func grad(_ hash: Int, _ x: Double) -> Double {
        return (hash & 1) == 0 ? x : -x
    }

    private static func grad2D(_ hash: Int, _ x: Double, _ y: Double) -> Double {
        let h = hash & 7
        let u = h < 4 ? x : y
        let v = h < 4 ? y : x
        return ((h & 1) == 0 ? u : -u) + ((h & 2) == 0 ? v * 2.0 : -v * 2.0)
    }
}

// MARK: - Data Structures
struct AlienWaveformSample {
    let upperHeight: CGFloat
    let lowerHeight: CGFloat
    let xDrift: CGFloat
    let glow: CGFloat

    var totalHeight: CGFloat {
        upperHeight + lowerHeight
    }
}

struct AlienWaveformProfile {
    let minHeight: CGFloat
    let maxHeight: CGFloat

    init(minHeight: CGFloat = 8, maxHeight: CGFloat = 45) {
        self.minHeight = minHeight
        self.maxHeight = max(minHeight * 2, maxHeight)
    }

    func samples(
        audioPower: Double,
        time: TimeInterval,
        count: Int = 37,
        isActive: Bool
    ) -> [AlienWaveformSample] {
        let sampleCount = max(2, count)
        let normalizedPower = max(0, min(1, audioPower))
        let activePower = min(1, pow(normalizedPower, 0.42) * 1.16)
        let span = maxHeight - minHeight * 2

        return (0..<sampleCount).map { index in
            let fraction = Double(index) / Double(sampleCount - 1)
            let centered = fraction * 2 - 1
            let envelope = 0.22 + 0.78 * exp(-pow(centered * 1.42, 2))
            
            // Continuous slowly drifting flows for resting states
            let slowFlow = sin(time * 1.5 - Double(index) * 0.23)
            let counterFlow = cos(time * 0.72 + Double(index) * 0.41)
            let filament = sin(time * 2.8 + Double(index) * 1.07)
            let liquid = 0.42 + 0.58 * abs(slowFlow * 0.52 + counterFlow * 0.34 + filament * 0.14)

            let energy: Double
            if isActive {
                energy = max(0.18, activePower) * envelope * liquid
            } else {
                energy = 0.08 + 0.20 * envelope * (0.55 + 0.45 * abs(counterFlow))
            }

            let totalHeight = minHeight * 2 + span * CGFloat(min(1, energy))
            let asymmetry = 0.5
                + 0.15 * sin(time * 1.12 + Double(index) * 0.39)
                + 0.05 * sin(Double(index) * 1.73)
            let upperShare = CGFloat(max(0.36, min(0.64, asymmetry)))
            let freeHeight = max(0, totalHeight - minHeight * 2)
            let upperHeight = minHeight + freeHeight * upperShare
            let lowerHeight = minHeight + freeHeight * (1 - upperShare)
            let xDrift = CGFloat(slowFlow * 12 + counterFlow * 8 + filament * 4)
            let glow = CGFloat(max(0.24, min(1, energy)))

            return AlienWaveformSample(
                upperHeight: upperHeight,
                lowerHeight: lowerHeight,
                xDrift: xDrift,
                glow: glow
            )
        }
    }
}

// MARK: - AudioVisualizer Component
struct AudioVisualizer: View {
    let audioMeter: AudioMeter
    let color: Color
    let isActive: Bool

    @AppStorage("visualizerWaveformHeight") private var visualizerWaveformHeight = 75.0

    var body: some View {
        let profile = AlienWaveformProfile(minHeight: 8, maxHeight: CGFloat(visualizerWaveformHeight))
        TimelineView(.animation(minimumInterval: 0.016)) { context in
            AlienWaveformCanvas(
                samples: profile.samples(
                    audioPower: audioMeter.averagePower,
                    time: context.date.timeIntervalSinceReferenceDate,
                    isActive: isActive
                ),
                baseColor: color,
                isActive: isActive,
                maxHeight: profile.maxHeight,
                time: context.date.timeIntervalSinceReferenceDate
            )
        }
        .frame(maxWidth: .infinity, idealHeight: CGFloat(visualizerWaveformHeight), maxHeight: CGFloat(visualizerWaveformHeight))
    }
}

struct StaticVisualizer: View {
    let color: Color
    
    @AppStorage("visualizerWaveformHeight") private var visualizerWaveformHeight = 75.0

    var body: some View {
        let profile = AlienWaveformProfile(minHeight: 8, maxHeight: CGFloat(visualizerWaveformHeight))
        TimelineView(.animation(minimumInterval: 0.033)) { context in
            AlienWaveformCanvas(
                samples: profile.samples(
                    audioPower: 0,
                    time: context.date.timeIntervalSinceReferenceDate,
                    isActive: false
                ),
                baseColor: color,
                isActive: false,
                maxHeight: profile.maxHeight,
                time: context.date.timeIntervalSinceReferenceDate
            )
        }
        .frame(maxWidth: .infinity, idealHeight: CGFloat(visualizerWaveformHeight), maxHeight: CGFloat(visualizerWaveformHeight))
    }
}

// MARK: - Alien Waveform Canvas Redesign (Organic Multi-Strand 3D Mesh)
private struct AlienWaveformCanvas: View {
    let samples: [AlienWaveformSample]
    let baseColor: Color
    let isActive: Bool
    let maxHeight: CGFloat
    let time: TimeInterval

    @AppStorage("visualizerSpeed") private var visualizerSpeed = 1.0
    @AppStorage("visualizerParticleColor") private var visualizerParticleColor = "orange"
    @AppStorage("visualizerParticleShape") private var visualizerParticleShape = "orbiting"
    @AppStorage("visualizerMovementType") private var visualizerMovementType = "alien"
    @AppStorage("visualizerLineTheme") private var visualizerLineTheme = "cyber"

    // Color definitions for light-cement high contrast compatibility
    private let electricPurple = Color(red: 0.54, green: 0.12, blue: 0.92)
    private let whiteBlue = Color(red: 0.28, green: 0.58, blue: 0.95)
    private let deepViolet = Color(red: 0.32, green: 0.02, blue: 0.78)
    private let neonIndigo = Color(red: 0.42, green: 0.38, blue: 0.98)
    private let neonBlue = Color(red: 0.18, green: 0.62, blue: 0.92)

    struct WaveThemeColors {
        let primaryGradient: [Color]
        let secondaryGradient: [Color]
        let subtleColor: Color
        let glowColor: Color
    }
    
    private var themeColors: WaveThemeColors {
        if UserDefaults.standard.bool(forKey: "superchargeAdaptiveColorExtraction") {
            #if canImport(AppKit)
            let nsAccent = NSColor.controlAccentColor
            let accent = Color(nsAccent)
            return WaveThemeColors(
                primaryGradient: [accent, accent.opacity(0.8), .white],
                secondaryGradient: [accent.opacity(0.7), Color.purple, Color.blue],
                subtleColor: accent.opacity(0.15),
                glowColor: accent
            )
            #else
            let accent = Color.accentColor
            return WaveThemeColors(
                primaryGradient: [accent, accent.opacity(0.8), .white],
                secondaryGradient: [accent.opacity(0.7), Color.purple, Color.blue],
                subtleColor: accent.opacity(0.15),
                glowColor: accent
            )
            #endif
        }

        switch visualizerLineTheme {
        case "sunset":
            return WaveThemeColors(
                primaryGradient: [Color(red: 1.0, green: 0.3, blue: 0.3), Color(red: 1.0, green: 0.6, blue: 0.1), .white],
                secondaryGradient: [Color(red: 0.9, green: 0.0, blue: 0.6), Color(red: 1.0, green: 0.2, blue: 0.4), Color(red: 1.0, green: 0.5, blue: 0.0)],
                subtleColor: Color(red: 1.0, green: 0.2, blue: 0.4).opacity(0.15),
                glowColor: Color(red: 1.0, green: 0.3, blue: 0.3)
            )
        case "matrix":
            return WaveThemeColors(
                primaryGradient: [Color(red: 0.0, green: 1.0, blue: 0.53), Color(red: 0.0, green: 0.66, blue: 0.42), .white],
                secondaryGradient: [Color(red: 0.0, green: 0.8, blue: 0.2), Color(red: 0.38, green: 0.94, blue: 1.0), Color(red: 0.0, green: 1.0, blue: 0.53)],
                subtleColor: Color(red: 0.0, green: 0.8, blue: 0.2).opacity(0.15),
                glowColor: Color(red: 0.0, green: 1.0, blue: 0.53)
            )
        case "aurora":
            return WaveThemeColors(
                primaryGradient: [Color(red: 0.0, green: 0.95, blue: 1.0), Color(red: 0.31, green: 0.67, blue: 1.0), .white],
                secondaryGradient: [Color(red: 0.5, green: 0.0, blue: 1.0), Color(red: 0.0, green: 0.95, blue: 1.0), Color(red: 0.31, green: 0.67, blue: 1.0)],
                subtleColor: Color(red: 0.0, green: 0.95, blue: 1.0).opacity(0.15),
                glowColor: Color(red: 0.0, green: 0.95, blue: 1.0)
            )
        case "mono":
            return WaveThemeColors(
                primaryGradient: [.white, Color(red: 0.88, green: 0.88, blue: 0.88), .white],
                secondaryGradient: [Color(red: 0.7, green: 0.7, blue: 0.7), Color(red: 0.4, green: 0.4, blue: 0.4), Color(red: 0.9, green: 0.9, blue: 0.9)],
                subtleColor: Color(red: 0.5, green: 0.5, blue: 0.5).opacity(0.12),
                glowColor: .white
            )
        default: // cyber (default)
            return WaveThemeColors(
                primaryGradient: [whiteBlue, neonBlue, .white],
                secondaryGradient: [electricPurple, deepViolet, neonIndigo],
                subtleColor: neonIndigo.opacity(0.15),
                glowColor: electricPurple
            )
        }
    }

    private var resolvedParticleColor: Color {
        switch visualizerParticleColor {
        case "orange": return Color(red: 1.0, green: 0.416, blue: 0.0) // Sci-Fi Orange
        case "purple": return electricPurple
        case "indigo": return neonIndigo
        case "white": return .white
        default: return Color(red: 1.0, green: 0.416, blue: 0.0)
        }
    }

    private func drawParticle(context: GraphicsContext, point: CGPoint, radius: CGFloat, scale: CGFloat, index: Int) {
        let cx: CGFloat
        let cy: CGFloat
        let r: CGFloat
        
        let adjustedTime = time * visualizerSpeed

        switch visualizerParticleShape {
        case "orbiting":
            let angle = adjustedTime * 5.0 + Double(index) * 1.1
            let orbitDist = 5.0 * scale
            cx = point.x + CGFloat(cos(angle)) * orbitDist
            cy = point.y + CGFloat(sin(angle)) * orbitDist
            r = radius * 0.85
        case "floating":
            let driftX = CGFloat(sin(adjustedTime * 3.0 + Double(index) * 1.7)) * 4.0 * scale
            let driftY = CGFloat(cos(adjustedTime * 2.5 + Double(index) * 1.2)) * 4.0 * scale
            cx = point.x + driftX
            cy = point.y + driftY
            r = radius
        case "scaling":
            let scaleFactor = 0.5 + 0.5 * sin(adjustedTime * 6.0 + Double(index) * 1.5)
            cx = point.x
            cy = point.y
            r = radius * CGFloat(scaleFactor)
        default: // static
            cx = point.x
            cy = point.y
            r = radius
        }
        
        let finalRadius = max(1.5, r)
        var path = Path()
        let shapeID = index % 3
        
        if shapeID == 0 {
            // 4-point star / cross
            path.move(to: CGPoint(x: cx, y: cy - finalRadius * 1.5))
            path.addLine(to: CGPoint(x: cx + finalRadius * 0.35, y: cy - finalRadius * 0.35))
            path.addLine(to: CGPoint(x: cx + finalRadius * 1.5, y: cy))
            path.addLine(to: CGPoint(x: cx + finalRadius * 0.35, y: cy + finalRadius * 0.35))
            path.addLine(to: CGPoint(x: cx, y: cy + finalRadius * 1.5))
            path.addLine(to: CGPoint(x: cx - finalRadius * 0.35, y: cy + finalRadius * 0.35))
            path.addLine(to: CGPoint(x: cx - finalRadius * 1.5, y: cy))
            path.addLine(to: CGPoint(x: cx - finalRadius * 0.35, y: cy - finalRadius * 0.35))
            path.closeSubpath()
        } else if shapeID == 1 {
            // Diamond
            path.move(to: CGPoint(x: cx, y: cy - finalRadius * 1.2))
            path.addLine(to: CGPoint(x: cx + finalRadius * 1.2, y: cy))
            path.addLine(to: CGPoint(x: cx, y: cy + finalRadius * 1.2))
            path.addLine(to: CGPoint(x: cx - finalRadius * 1.2, y: cy))
            path.closeSubpath()
        } else {
            // Circle
            path.addEllipse(in: CGRect(x: cx - finalRadius, y: cy - finalRadius, width: finalRadius * 2, height: finalRadius * 2))
        }
        
        let pColor = resolvedParticleColor
        var pContext = context
        pContext.addFilter(.shadow(color: pColor.opacity(0.85), radius: 6, x: 0, y: 0))
        pContext.fill(path, with: .color(pColor))
        
        var innerPath = Path()
        let innerR = max(0.6, finalRadius * 0.3)
        innerPath.addEllipse(in: CGRect(x: cx - innerR, y: cy - innerR, width: innerR * 2, height: innerR * 2))
        pContext.fill(innerPath, with: .color(.white))
    }

    var body: some View {
        Canvas { context, size in
            guard samples.count > 1, size.width > 0, size.height > 0 else { return }

            let scale = min(1, size.height / maxHeight)
            let midY = size.height / 2
            let sideInset: CGFloat = min(8, size.width * 0.04)
            let usableWidth = max(1, size.width - sideInset * 2)
            
            // 1. Background Dotted Columns Matrix Field
            let dotColumns = 14
            let dotsPerColumn = 10
            let columnStep = size.width / CGFloat(dotColumns - 1)
            let rowStep = size.height / CGFloat(dotsPerColumn - 1)
            let dotColor = Color(red: 0.65, green: 0.66, blue: 0.77) // Soft slate-lavender dot matrix
            
            for col in 0..<dotColumns {
                let colX = col == 0 ? sideInset : (col == dotColumns - 1 ? size.width - sideInset : CGFloat(col) * columnStep)
                let fractionX = CGFloat(col) / CGFloat(dotColumns - 1)
                let centeredX = fractionX * 2 - 1
                let envelopeX = exp(-pow(centeredX * 1.5, 2))
                
                for row in 0..<dotsPerColumn {
                    let rowY = CGFloat(row) * rowStep
                    let fractionY = CGFloat(row) / CGFloat(dotsPerColumn - 1)
                    let centeredY = fractionY * 2 - 1
                    
                    let powerMod = isActive ? (0.22 + 0.78 * CGFloat(samples.first?.glow ?? 0)) : 0.15
                    let baseOpacity = 0.24 * envelopeX * (1.0 - abs(centeredY)) * powerMod
                    
                    if baseOpacity > 0.01 {
                        let dotRadius = 1.0 + 0.6 * (1.0 - abs(centeredY)) * (isActive ? 1.4 : 1.0)
                        var dotPath = Path()
                        dotPath.addEllipse(in: CGRect(x: colX - dotRadius, y: rowY - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
                        context.fill(dotPath, with: .color(dotColor.opacity(Double(baseOpacity))))
                    }
                }
            }

            // 2. Generate multi-strand points (18 parallel organic threads of high resolution)
            let strandsCount = 18
            let stepsCount = 100 // high resolution points for organic curves
            var strandPoints: [[CGPoint]] = Array(repeating: [], count: strandsCount)
            let stepX = usableWidth / CGFloat(stepsCount - 1)
            
            let adjustedTime = time * visualizerSpeed

            for s in 0..<strandsCount {
                let layer = Double(s)
                let layerSpeed = 1.35 + sin(layer * 0.42) * 0.75
                let layerFrequency = 0.014 + cos(layer * 0.38) * 0.006
                let layerPhaseOffset = layer * 0.63

                for index in 0..<stepsCount {
                    let x = sideInset + CGFloat(index) * stepX
                    let fraction = CGFloat(index) / CGFloat(stepsCount - 1)

                    let sampleIndexFraction = fraction * CGFloat(samples.count - 1)
                    let baseSample = Int(floor(sampleIndexFraction))
                    let nextSample = min(samples.count - 1, baseSample + 1)
                    let tFrac = sampleIndexFraction - CGFloat(baseSample)

                    let sGlow = samples[baseSample].glow + tFrac * (samples[nextSample].glow - samples[baseSample].glow)
                    let sUpper = samples[baseSample].upperHeight + tFrac * (samples[nextSample].upperHeight - samples[baseSample].upperHeight)
                    let sLower = samples[baseSample].lowerHeight + tFrac * (samples[nextSample].lowerHeight - samples[baseSample].lowerHeight)
                    let sDrift = samples[baseSample].xDrift + tFrac * (samples[nextSample].xDrift - samples[baseSample].xDrift)

                    let phase = Double(x) * layerFrequency + adjustedTime * layerSpeed + layerPhaseOffset
                    let noiseVal = WaveNoise.fbm2D(Double(x) * 0.009 + adjustedTime * 0.04, layer * 0.47)

                    let envelopeY = 0.25 + 0.75 * exp(-pow((fraction * 2.0 - 1.0) * 1.5, 2.0))
                    let baseMaxAmp = (sUpper + sLower) * 0.55 * scale
                    
                    let amplitude = baseMaxAmp * (0.35 + 0.65 * CGFloat(sin(layer * 0.55))) * envelopeY
                    let secondaryAmplitude = amplitude * 0.36
                    let organicAmount = (isActive ? 14.0 : 4.0) * (0.4 + 0.6 * CGFloat(noiseVal)) * envelopeY

                    let yOffset: CGFloat
                    let finalX: CGFloat
                    if visualizerMovementType == "classic" {
                        // Structured, smooth sine-ribbon wave calculations
                        yOffset = CGFloat(sin(phase)) * amplitude
                                    + CGFloat(sin(phase * 0.43 + adjustedTime * 0.65)) * secondaryAmplitude
                        finalX = x
                    } else {
                        // Turbulent organic "alien" drift wave calculations
                        yOffset = CGFloat(sin(phase)) * amplitude
                                    + CGFloat(sin(phase * 0.43 + adjustedTime * 0.65)) * secondaryAmplitude
                                    + CGFloat(noiseVal) * organicAmount
                                    + sDrift * 0.08 * scale
                        finalX = x + sDrift * 0.12 * (1.0 - abs(fraction * 2.0 - 1.0)) * scale
                    }
                    let finalY = midY + yOffset
                    strandPoints[s].append(CGPoint(x: finalX, y: finalY))
                }
            }

            // 3. Render 3D Liquid Volume Shading (Translucent filled background layer)
            var boundaryTop: [CGPoint] = []
            var boundaryBottom: [CGPoint] = []
            for idx in 0..<stepsCount {
                var minY = midY
                var maxY = midY
                for s in 0..<strandsCount {
                    let ptY = strandPoints[s][idx].y
                    if ptY < minY { minY = ptY }
                    if ptY > maxY { maxY = ptY }
                }
                let ptX = strandPoints[0][idx].x
                boundaryTop.append(CGPoint(x: ptX, y: minY))
                boundaryBottom.append(CGPoint(x: ptX, y: maxY))
            }

            let fillPath = closedContourPath(top: boundaryTop, bottom: boundaryBottom)
            let fillGradient = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [
                    themeColors.glowColor.opacity(isActive ? 0.15 : 0.06),
                    themeColors.primaryGradient[0].opacity(isActive ? 0.10 : 0.04),
                    themeColors.secondaryGradient[0].opacity(isActive ? 0.12 : 0.04)
                ]),
                startPoint: CGPoint(x: 0, y: midY),
                endPoint: CGPoint(x: size.width, y: midY)
            )
            context.fill(fillPath, with: fillGradient)

            // 4. Render Warped Mesh Ribs (Latitudinal cross-lines with turbulence displacement)
            let ribStep = isActive ? 4 : 6
            for idx in stride(from: 4, to: stepsCount - 4, by: ribStep) {
                var ribPath = Path()
                ribPath.move(to: strandPoints[0][idx])
                for s in 1..<strandsCount {
                    if visualizerMovementType == "classic" {
                        let originalPt = strandPoints[s][idx]
                        ribPath.addLine(to: originalPt)
                    } else {
                        let noiseVal = WaveNoise.noise2D(Double(idx) * 0.15, Double(s) * 0.25 + adjustedTime * 0.8)
                        let turbulenceOffset = CGFloat(noiseVal) * (isActive ? 2.5 : 0.8)
                        let originalPt = strandPoints[s][idx]
                        ribPath.addLine(to: CGPoint(x: originalPt.x + turbulenceOffset, y: originalPt.y))
                    }
                }
                context.stroke(
                    ribPath,
                    with: .color(themeColors.glowColor.opacity(isActive ? 0.18 : 0.06)),
                    style: StrokeStyle(lineWidth: 0.45 * scale, lineCap: .round)
                )
            }

            // 5. Render Outer Organic Strands with varying styles and gradients
            for s in 0..<strandsCount {
                let path = smoothedPath(through: strandPoints[s])
                let colorGradient: GraphicsContext.Shading
                let thickness: CGFloat

                if s == 3 || s == 8 || s == 14 {
                    colorGradient = .linearGradient(
                        Gradient(colors: themeColors.primaryGradient),
                        startPoint: CGPoint(x: 0, y: midY),
                        endPoint: CGPoint(x: size.width, y: midY)
                    )
                    thickness = (isActive ? 1.85 : 0.9) * scale
                } else if s.isMultiple(of: 3) {
                    colorGradient = .linearGradient(
                        Gradient(colors: themeColors.secondaryGradient),
                        startPoint: CGPoint(x: 0, y: midY),
                        endPoint: CGPoint(x: size.width, y: midY)
                    )
                    thickness = (isActive ? 1.4 : 0.75) * scale
                } else {
                    colorGradient = .color(themeColors.subtleColor.opacity(isActive ? 0.32 : 0.12))
                    thickness = 0.5 * scale
                }

                var strandContext = context
                if s == 3 || s == 14 {
                    let shadowColor = s == 3 ? themeColors.primaryGradient[0] : themeColors.secondaryGradient[0]
                    strandContext.addFilter(
                        .shadow(
                            color: shadowColor.opacity(isActive ? 0.75 : 0.25),
                            radius: isActive ? 10 : 3,
                            x: 0,
                            y: 0
                        )
                    )
                }
                
                strandContext.stroke(
                    path,
                    with: colorGradient,
                    style: StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round)
                )
            }

            // 6. Glowing nodes at high-energy intersections (custom sci-fi animated shapes and colors)
            if isActive {
                for idx in stride(from: 10, to: stepsCount - 10, by: 12) {
                    let fraction = CGFloat(idx) / CGFloat(stepsCount - 1)
                    let sampleIdx = Int(fraction * CGFloat(samples.count - 1))
                    
                    if samples[sampleIdx].glow > 0.45 {
                        let targetStrand = idx.isMultiple(of: 24) ? 3 : 14
                        let point = strandPoints[targetStrand][idx]
                        let radius = (2.2 + samples[sampleIdx].glow * 2.0) * scale
                        
                        drawParticle(context: context, point: point, radius: radius, scale: scale, index: idx)
                    }
                }
            }

            // 7. Supercharged Metal Fluid Particle Visualizer
            if UserDefaults.standard.bool(forKey: "superchargeMetalFluidVisualizer") {
                let fluidParticlesCount = 45
                for p in 0..<fluidParticlesCount {
                    let seed = Double(p)
                    let progress = fract(adjustedTime * 0.12 + seed * 0.022)
                    let px = sideInset + CGFloat(progress) * usableWidth
                    
                    let fraction = CGFloat(px - sideInset) / usableWidth
                    let sampleIndexFraction = fraction * CGFloat(samples.count - 1)
                    let baseSample = Int(floor(sampleIndexFraction))
                    let nextSample = min(samples.count - 1, baseSample + 1)
                    let tFrac = sampleIndexFraction - CGFloat(baseSample)
                    
                    let sUpper = samples[baseSample].upperHeight + tFrac * (samples[nextSample].upperHeight - samples[baseSample].upperHeight)
                    let sLower = samples[baseSample].lowerHeight + tFrac * (samples[nextSample].lowerHeight - samples[baseSample].lowerHeight)
                    
                    let swirlY = WaveNoise.noise2D(seed * 1.5, adjustedTime * 1.8) * Double(sUpper + sLower) * 0.65 * Double(scale)
                    let swirlX = WaveNoise.noise2D(adjustedTime * 1.2, seed * 2.3) * 12.0 * Double(scale)
                    
                    let py = midY + CGFloat(swirlY)
                    let finalPX = px + CGFloat(swirlX)
                    
                    if finalPX > sideInset && finalPX < size.width - sideInset {
                        let baseSize: CGFloat = 1.2 + CGFloat(WaveNoise.noise1D(seed + adjustedTime) + 1.0) * 1.0
                        let opacity = 0.35 + 0.65 * sin(progress * .pi)
                        
                        var path = Path()
                        path.addEllipse(in: CGRect(x: finalPX - baseSize, y: py - baseSize, width: baseSize * 2, height: baseSize * 2))
                        
                        let fluidColor = themeColors.primaryGradient[p % 2].opacity(opacity)
                        var fluidContext = context
                        fluidContext.addFilter(.shadow(color: fluidColor, radius: 4, x: 0, y: 0))
                        fluidContext.fill(path, with: .color(fluidColor))
                    }
                }
            }
        }
    }

    private func fract(_ x: Double) -> Double {
        return x - floor(x)
    }

    private func smoothedPath(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let midpoint = CGPoint(
                x: (previous.x + current.x) / 2,
                y: (previous.y + current.y) / 2
            )
            path.addQuadCurve(to: midpoint, control: previous)
        }

        if let last = points.last {
            path.addLine(to: last)
        }
        return path
    }

    private func closedContourPath(top: [CGPoint], bottom: [CGPoint]) -> Path {
        var path = smoothedPath(through: top)
        for point in bottom.reversed() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
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
