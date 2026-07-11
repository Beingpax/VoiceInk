import SwiftUI

struct ConfettiCelebrationOverlay: View {
    @State private var startDate = Date()

    private enum Metrics {
        static let particleCount = 1_000
        static let duration: TimeInterval = 3.0
        static let buttonCenterBottomOffset: CGFloat = 49
    }

    private static let particles = (0..<Metrics.particleCount).map(ConfettiCelebrationParticle.init)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(startDate)
                let origin = CGPoint(
                    x: size.width / 2,
                    y: size.height - Metrics.buttonCenterBottomOffset
                )

                drawBurstFlash(elapsed: elapsed, origin: origin, in: context)

                for particle in Self.particles {
                    draw(
                        particle,
                        elapsed: elapsed,
                        origin: origin,
                        in: context
                    )
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onAppear {
            startDate = Date()
        }
    }

    private func drawBurstFlash(
        elapsed: TimeInterval,
        origin: CGPoint,
        in context: GraphicsContext
    ) {
        guard elapsed <= 0.42 else { return }

        let progress = min(max(elapsed / 0.42, 0), 1)
        let radius = 10 + progress * 58
        let opacity = (1 - progress) * 0.34
        let rect = CGRect(
            x: origin.x - radius / 2,
            y: origin.y - radius / 2,
            width: radius,
            height: radius
        )

        context.stroke(
            Path(ellipseIn: rect),
            with: .color(AppTheme.Accent.primary.opacity(opacity)),
            lineWidth: max(1, 4 * (1 - progress))
        )
    }

    private func draw(
        _ particle: ConfettiCelebrationParticle,
        elapsed: TimeInterval,
        origin: CGPoint,
        in context: GraphicsContext
    ) {
        let time = elapsed - particle.delay
        guard time >= 0, time <= Metrics.duration else { return }

        let progressTime = CGFloat(time)
        let x =
            origin.x + particle.startJitter.width + particle.velocity.width * progressTime + CGFloat(
                sin((time * particle.wobbleSpeed) + particle.phase)) * particle.wobble
        let y =
            origin.y + particle.startJitter.height + particle.velocity.height * progressTime + 0.5 * particle.gravity
            * progressTime * progressTime

        let fadeIn = min(time / 0.06, 1)
        let fadeOut = max(0, 1 - max(0, time - particle.fadeStart) / particle.fadeDuration)
        let opacity = fadeIn * fadeOut * particle.opacity
        guard opacity > 0.01 else { return }

        var localContext = context
        localContext.translateBy(x: x, y: y)
        localContext.rotate(by: .degrees(particle.rotation + particle.spin * time))

        let rect = CGRect(
            x: -particle.size.width / 2,
            y: -particle.size.height / 2,
            width: particle.size.width,
            height: particle.size.height
        )

        localContext.fill(
            path(for: particle.shape, in: rect),
            with: .color(particle.color.opacity(opacity))
        )
    }

    private func path(for shape: ConfettiCelebrationShape, in rect: CGRect) -> Path {
        switch shape {
        case .circle:
            return Path(ellipseIn: rect)
        case .diamond:
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
            return path
        case .ribbon:
            return Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) / 3)
        case .spark:
            let inset = min(rect.width, rect.height) * 0.22
            return Path(roundedRect: rect.insetBy(dx: inset, dy: 0), cornerRadius: 1)
        case .triangle:
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }
}

private struct ConfettiCelebrationPresenter: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPresented = false
    @State private var celebrationID = UUID()
    @State private var dismissalWorkItem: DispatchWorkItem?

    private enum Metrics {
        static let presentationDuration: TimeInterval = 3.25
        static let reducedMotionDuration: TimeInterval = 1.4
        static let overlayZIndex: Double = 20
    }

    func body(content: Content) -> some View {
        ZStack {
            content

            if isPresented {
                Group {
                    if reduceMotion {
                        ReducedMotionCelebrationOverlay()
                    } else {
                        ConfettiCelebrationOverlay()
                    }
                }
                .id(celebrationID)
                .allowsHitTesting(false)
                .transition(.opacity)
                .zIndex(Metrics.overlayZIndex)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .licenseCelebrationRequested)) { _ in
            showCelebration()
        }
        .onDisappear {
            dismissalWorkItem?.cancel()
            dismissalWorkItem = nil
        }
    }

    private func showCelebration() {
        dismissalWorkItem?.cancel()
        celebrationID = UUID()

        withAnimation(.easeOut(duration: 0.16)) {
            isPresented = true
        }

        let duration = reduceMotion ? Metrics.reducedMotionDuration : Metrics.presentationDuration
        let workItem = DispatchWorkItem { [isPresentedBinding = $isPresented] in
            withAnimation(.easeOut(duration: 0.24)) {
                isPresentedBinding.wrappedValue = false
            }
        }

        dismissalWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }
}

private struct ReducedMotionCelebrationOverlay: View {
    var body: some View {
        ZStack {
            Color.clear

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(AppTheme.Status.positive)
                .padding(22)
                .background(
                    Circle()
                        .fill(AppTheme.Surface.control)
                )
                .overlay {
                    Circle()
                        .stroke(AppTheme.Border.control, lineWidth: 1)
                }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    func confettiCelebrationPresenter() -> some View {
        modifier(ConfettiCelebrationPresenter())
    }
}

private struct ConfettiCelebrationParticle {
    let color: Color
    let shape: ConfettiCelebrationShape
    let size: CGSize
    let delay: TimeInterval
    let startJitter: CGSize
    let velocity: CGSize
    let gravity: CGFloat
    let rotation: Double
    let spin: Double
    let wobble: CGFloat
    let wobbleSpeed: Double
    let phase: Double
    let fadeStart: TimeInterval
    let fadeDuration: TimeInterval
    let opacity: Double

    init(id: Int) {
        var random = ConfettiSeededRandom(seed: UInt64(id + 1) * 19_171)
        let angle = random.range(62, 118) * Double.pi / 180
        let speed = random.range(900, 1_300)
        let width = CGFloat(random.range(2.5, 7.5))
        let height = CGFloat(random.range(4, 13))

        self.color = Self.palette[id % Self.palette.count]
        self.shape = ConfettiCelebrationShape(rawValue: id % ConfettiCelebrationShape.allCases.count) ?? .ribbon
        self.size =
            shape == .circle
            ? CGSize(width: width, height: width)
            : CGSize(width: width, height: height)
        self.delay = random.range(0, 0.24)
        self.startJitter = CGSize(
            width: CGFloat(random.signedRange(0, 7)),
            height: CGFloat(random.signedRange(0, 5))
        )
        self.velocity = CGSize(
            width: CGFloat(cos(angle) * speed),
            height: CGFloat(-sin(angle) * speed)
        )
        self.gravity = CGFloat(random.range(780, 980))
        self.rotation = random.range(0, 360)
        self.spin = random.signedRange(150, 620)
        self.wobble = CGFloat(random.range(1, 15))
        self.wobbleSpeed = random.range(5, 13)
        self.phase = random.range(0, .pi * 2)
        self.fadeStart = random.range(1.48, 2.08)
        self.fadeDuration = random.range(0.62, 0.94)
        self.opacity = random.range(0.58, 0.94)
    }

    private static let palette: [Color] = [
        AppTheme.Accent.primary,
        AppTheme.Accent.strong,
        AppTheme.Status.positive,
        AppTheme.Status.infoStrong,
        AppTheme.Status.warningStrong,
        Color(nsColor: .systemOrange),
        Color(nsColor: .systemPink),
        Color.primary.opacity(0.72),
    ]
}

private enum ConfettiCelebrationShape: Int, CaseIterable {
    case ribbon
    case circle
    case triangle
    case diamond
    case spark
}

private struct ConfettiSeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func range(_ lowerBound: Double, _ upperBound: Double) -> Double {
        lowerBound + nextUnit() * (upperBound - lowerBound)
    }

    mutating func signedRange(_ lowerBound: Double, _ upperBound: Double) -> Double {
        (nextUnit() < 0.5 ? -1 : 1) * range(lowerBound, upperBound)
    }

    private mutating func nextUnit() -> Double {
        state = 6_364_136_223_846_793_005 &* state &+ 1
        return Double((state >> 11) & 0x1F_FFFF_FFFF_FFFF) / Double(0x1F_FFFF_FFFF_FFFF)
    }
}
