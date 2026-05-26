import SwiftUI
import AVFoundation

extension TimeInterval {
    func formatTiming() -> String {
        if self < 1 {
            return String(format: "%.0fms", self * 1000)
        }
        if self < 60 {
            return String(format: "%.1fs", self)
        }
        let minutes = Int(self) / 60
        let seconds = self.truncatingRemainder(dividingBy: 60)
        return String(format: "%dm %.0fs", minutes, seconds)
    }
}

class WaveformGenerator {
    private static let cache = NSCache<NSString, NSArray>()

    static func generateWaveformSamples(from url: URL, sampleCount: Int = 200) async -> [Float] {
        let cacheKey = url.absoluteString as NSString

        if let cachedSamples = cache.object(forKey: cacheKey) as? [Float] {
            return cachedSamples
        }
        guard let audioFile = try? AVAudioFile(forReading: url) else { return [] }
        let format = audioFile.processingFormat
        let frameCount = UInt32(audioFile.length)
        let stride = max(1, Int(frameCount) / sampleCount)
        let bufferSize = min(UInt32(4096), frameCount)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferSize) else { return [] }

        do {
            var maxValues = [Float](repeating: 0.0, count: sampleCount)
            var sampleIndex = 0
            var framePosition: AVAudioFramePosition = 0

            while sampleIndex < sampleCount && framePosition < AVAudioFramePosition(frameCount) {
                audioFile.framePosition = framePosition
                try audioFile.read(into: buffer)

                if let channelData = buffer.floatChannelData?[0], buffer.frameLength > 0 {
                    maxValues[sampleIndex] = abs(channelData[0])
                    sampleIndex += 1
                }

                framePosition += AVAudioFramePosition(stride)
            }

            let normalizedSamples: [Float]
            if let maxSample = maxValues.max(), maxSample > 0 {
                normalizedSamples = maxValues.map { $0 / maxSample }
            } else {
                normalizedSamples = maxValues
            }

            cache.setObject(normalizedSamples as NSArray, forKey: cacheKey)
            return normalizedSamples
        } catch {
            print("Error reading audio file: \(error)")
            return []
        }
    }
}

class AudioPlayerManager: ObservableObject {
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var waveformSamples: [Float] = []
    @Published var isLoadingWaveform = false
    @Published var playbackRate: Float = {
        let saved = UserDefaults.standard.float(forKey: "audioPlaybackRate")
        return saved > 0 ? saved : 1.0
    }() {
        didSet { UserDefaults.standard.set(playbackRate, forKey: "audioPlaybackRate") }
    }
    
    func loadAudio(from url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.enableRate = true
            audioPlayer?.prepareToPlay()
            duration = audioPlayer?.duration ?? 0
            isLoadingWaveform = true
            
            Task {
                let samples = await WaveformGenerator.generateWaveformSamples(from: url)
                await MainActor.run {
                    self.waveformSamples = samples
                    self.isLoadingWaveform = false
                }
            }
        } catch {
            print("Error loading audio: \(error.localizedDescription)")
        }
    }
    
    func play() {
        audioPlayer?.rate = playbackRate
        audioPlayer?.play()
        isPlaying = true
        startTimer()
    }

    func cyclePlaybackRate() {
        switch playbackRate {
        case 1.0:  playbackRate = 1.5
        case 1.5:  playbackRate = 2.0
        default:   playbackRate = 1.0
        }
        audioPlayer?.rate = playbackRate
    }
    
    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopTimer()
    }
    
    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        currentTime = time
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.currentTime = self.audioPlayer?.currentTime ?? 0
            if self.currentTime >= self.duration {
                self.pause()
                self.seek(to: 0)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func cleanup() {
        stopTimer()
        audioPlayer?.stop()
        audioPlayer = nil
    }

    deinit {
        cleanup()
    }
}

private func formatTime(_ time: TimeInterval) -> String {
    let minutes = Int(time) / 60
    let seconds = Int(time) % 60
    return String(format: "%d:%02d", minutes, seconds)
}

struct WaveformView: View {
    let samples: [Float]
    let currentTime: TimeInterval
    let duration: TimeInterval
    let isLoading: Bool
    var onSeek: (Double) -> Void
    @State private var isHovering = false
    @State private var hoverLocation: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                if isLoading {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading...")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    PlaybackAlienWaveform(
                        samples: samples,
                        progress: duration > 0 ? CGFloat(currentTime / duration) : 0,
                        isHovering: isHovering,
                        hoverProgress: geometry.size.width > 0 ? hoverLocation / geometry.size.width : 0
                    )
                    .opacity(0.82)
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 2)

                    if isHovering {
                        Text(formatTime(duration * Double(hoverLocation / geometry.size.width)))
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.accentColor))
                            .offset(x: max(0, min(hoverLocation - 25, geometry.size.width - 50)))
                            .offset(y: -26)

                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 2)
                            .frame(maxHeight: .infinity)
                            .offset(x: hoverLocation)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isLoading {
                            hoverLocation = value.location.x
                            onSeek(Double(value.location.x / geometry.size.width) * duration)
                        }
                    }
            )
            .onHover { hovering in
                if !isLoading {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isHovering = hovering
                    }
                }
            }
            .onContinuousHover { phase in
                if !isLoading {
                    if case .active(let location) = phase {
                        hoverLocation = location.x
                    }
                }
            }
        }
        .frame(height: 32)
    }
}

private struct PlaybackAlienWaveform: View {
    let samples: [Float]
    let progress: CGFloat
    let isHovering: Bool
    let hoverProgress: CGFloat

    private let gradientColors = [
        Color(red: 0.58, green: 0.22, blue: 0.95), // Electric Purple
        Color(red: 0.48, green: 0.58, blue: 0.68),  // Cement / Gray-Blue
        Color(red: 0.52, green: 0.32, blue: 1.0)   // Violet/Purple
    ]

    var body: some View {
        Canvas { context, size in
            guard samples.count > 1, size.width > 0, size.height > 0 else { return }

            let midY = size.height / 2
            let visibleSamples = reducedSamples(for: size.width)
            let step = size.width / CGFloat(max(1, visibleSamples.count - 1))
            let hoverX = max(0, min(size.width, hoverProgress * size.width))
            var topPoints: [CGPoint] = []
            var bottomPoints: [CGPoint] = []
            var centerPoints: [CGPoint] = []

            for (index, sample) in visibleSamples.enumerated() {
                let x = CGFloat(index) * step
                let drift = sin(Double(index) * 0.62) * 3.6 + cos(Double(index) * 0.19) * 2.2
                let hoverLift = isHovering ? max(0, 1 - abs(x - hoverX) / 42) * 4.0 : 0
                let amplitude = max(0.08, CGFloat(sample))
                let upper = 3.5 + amplitude * (size.height * 0.38 + hoverLift)
                let lower = 3.5 + amplitude * (size.height * 0.30 + hoverLift * 0.7)
                let center = CGPoint(x: x + CGFloat(drift) * 0.28, y: midY + CGFloat(drift) * 0.18)
                topPoints.append(CGPoint(x: center.x + CGFloat(drift) * 0.35, y: center.y - upper))
                bottomPoints.append(CGPoint(x: center.x - CGFloat(drift) * 0.25, y: center.y + lower))
                centerPoints.append(center)
            }

            // Calculate longitudinal meridians for the volumetric grid/wireframe mesh in playback
            let meridiansCount = 7
            var meridianPoints: [[CGPoint]] = Array(repeating: [], count: meridiansCount)

            for index in 0..<visibleSamples.count {
                let top = topPoints[index]
                let bottom = bottomPoints[index]
                
                for m in 0..<meridiansCount {
                    let fraction = CGFloat(m) / CGFloat(meridiansCount - 1)
                    
                    // Subtle hover/playback undulating wave modulation
                    let wavePhase = Double(m) * 0.45 + Double(index) * 0.22
                    let wiggle = sin(wavePhase) * (isHovering ? 1.5 : 0.5)
                    
                    let x = top.x + (bottom.x - top.x) * fraction
                    let y = top.y + (bottom.y - top.y) * fraction + wiggle
                    meridianPoints[m].append(CGPoint(x: x, y: y))
                }
            }

            let purpleGlow = Color(red: 0.58, green: 0.22, blue: 0.95)
            let cementGlow = Color(red: 0.48, green: 0.58, blue: 0.68)

            // Function to draw the mesh with specific opacity/glowing parameters
            let drawMesh = { (ctx: GraphicsContext, isPlayed: Bool) in
                let opacity: CGFloat = isPlayed ? 1.0 : 0.28
                let fillOpacity: CGFloat = isPlayed ? 0.12 : 0.04
                let lineMultiplier: CGFloat = isPlayed ? 1.0 : 0.6
                
                // 1. Fill
                let fillGradient = GraphicsContext.Shading.linearGradient(
                    Gradient(colors: [
                        purpleGlow.opacity(Double(fillOpacity)),
                        cementGlow.opacity(Double(fillOpacity * 0.7)),
                        purpleGlow.opacity(Double(fillOpacity))
                    ]),
                    startPoint: CGPoint(x: 0, y: midY),
                    endPoint: CGPoint(x: size.width, y: midY)
                )
                ctx.fill(closedWaveformPath(top: topPoints, bottom: bottomPoints), with: fillGradient)

                // 2. Ribs
                let ribStep = isPlayed ? 2 : 4
                for idx in stride(from: 1, to: visibleSamples.count - 1, by: ribStep) {
                    var ribPath = Path()
                    ribPath.move(to: meridianPoints[0][idx])
                    for m in 1..<meridiansCount {
                        ribPath.addLine(to: meridianPoints[m][idx])
                    }
                    ctx.stroke(
                        ribPath,
                        with: .color(Color(white: 0.55).opacity(isPlayed ? 0.15 : 0.05)),
                        style: StrokeStyle(lineWidth: 0.5 * lineMultiplier, lineCap: .round)
                    )
                }

                // 3. Longitudinal grid lines
                for m in 1..<(meridiansCount - 1) {
                    ctx.stroke(
                        smoothedPath(through: meridianPoints[m]),
                        with: .color(Color(white: 0.52).opacity(isPlayed ? 0.18 : 0.06)),
                        style: StrokeStyle(lineWidth: 0.6 * lineMultiplier, lineCap: .round, lineJoin: .round)
                    )
                }

                // 4. Cement/Gray-Blue Glowing Ribbon (using 3rd meridian)
                var cementContext = ctx
                if isPlayed {
                    cementContext.addFilter(.shadow(color: cementGlow.opacity(0.65), radius: 8, x: 0, y: 0))
                }
                cementContext.stroke(
                    smoothedPath(through: meridianPoints[2]),
                    with: .linearGradient(
                        Gradient(colors: [cementGlow.opacity(Double(opacity)), Color(red: 0.52, green: 0.32, blue: 1.0).opacity(Double(opacity))]),
                        startPoint: CGPoint(x: 0, y: midY),
                        endPoint: CGPoint(x: size.width, y: midY)
                    ),
                    style: StrokeStyle(lineWidth: (isPlayed ? 2.2 : 1.1), lineCap: .round, lineJoin: .round)
                )

                // 5. Electric Purple Glowing Ribbon (using 5th meridian)
                var purpleContext = ctx
                if isPlayed {
                    purpleContext.addFilter(.shadow(color: purpleGlow.opacity(0.65), radius: 8, x: 0, y: 0))
                }
                purpleContext.stroke(
                    smoothedPath(through: meridianPoints[4]),
                    with: .linearGradient(
                        Gradient(colors: [purpleGlow.opacity(Double(opacity)), Color(red: 0.52, green: 0.32, blue: 1.0).opacity(Double(opacity))]),
                        startPoint: CGPoint(x: 0, y: midY),
                        endPoint: CGPoint(x: size.width, y: midY)
                    ),
                    style: StrokeStyle(lineWidth: (isPlayed ? 2.0 : 1.0), lineCap: .round, lineJoin: .round)
                )

                // 6. Contours
                var topContext = ctx
                if isPlayed {
                    topContext.addFilter(.shadow(color: cementGlow.opacity(0.35), radius: 4, x: 0, y: 0))
                }
                topContext.stroke(
                    smoothedPath(through: topPoints),
                    with: .linearGradient(
                        Gradient(colors: [cementGlow.opacity(Double(opacity)), purpleGlow.opacity(Double(opacity * 0.6))]),
                        startPoint: CGPoint(x: 0, y: midY),
                        endPoint: CGPoint(x: size.width, y: midY)
                    ),
                    style: StrokeStyle(lineWidth: (isPlayed ? 1.5 : 0.8), lineCap: .round, lineJoin: .round)
                )

                var bottomContext = ctx
                if isPlayed {
                    bottomContext.addFilter(.shadow(color: purpleGlow.opacity(0.35), radius: 4, x: 0, y: 0))
                }
                bottomContext.stroke(
                    smoothedPath(through: bottomPoints),
                    with: .linearGradient(
                        Gradient(colors: [purpleGlow.opacity(Double(opacity)), cementGlow.opacity(Double(opacity * 0.6))]),
                        startPoint: CGPoint(x: 0, y: midY),
                        endPoint: CGPoint(x: size.width, y: midY)
                    ),
                    style: StrokeStyle(lineWidth: (isPlayed ? 1.35 : 0.7), lineCap: .round, lineJoin: .round)
                )

                // Center line
                ctx.stroke(
                    smoothedPath(through: centerPoints),
                    with: .color(isPlayed ? .primary.opacity(0.24) : .primary.opacity(0.08)),
                    style: StrokeStyle(lineWidth: 0.65, lineCap: .round, lineJoin: .round, dash: [3.5, 7.0])
                )
            }

            // Draw unplayed background
            drawMesh(context, false)

            // Draw played/glowing layer clipped to progress
            var playedContext = context
            playedContext.clip(to: Path(CGRect(x: 0, y: 0, width: size.width * max(0, min(1, progress)), height: size.height)))
            drawMesh(playedContext, true)
        }
    }

    private func reducedSamples(for width: CGFloat) -> [Float] {
        let targetCount = max(24, min(80, Int(width / 5)))
        let strideCount = max(1, samples.count / targetCount)
        let reduced = samples.enumerated().compactMap { index, sample in
            index.isMultiple(of: strideCount) ? sample : nil
        }
        return reduced.count > 1 ? reduced : samples
    }

    private func color(at location: CGFloat, opacity: CGFloat) -> Color {
        let safeOpacity = Double(max(0, min(1, opacity)))
        if location < 0.34 {
            return gradientColors[0].opacity(safeOpacity)
        }
        if location < 0.68 {
            return gradientColors[1].opacity(safeOpacity)
        }
        return gradientColors[2].opacity(safeOpacity)
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

    private func closedWaveformPath(top: [CGPoint], bottom: [CGPoint]) -> Path {
        var path = smoothedPath(through: top)
        for point in bottom.reversed() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

struct WaveformBar: View {
    let sample: Float
    let isPlayed: Bool
    let totalBars: Int
    let geometryWidth: CGFloat
    let isHovering: Bool
    let hoverProgress: CGFloat
    
    private var isNearHover: Bool {
        let barPosition = geometryWidth / CGFloat(totalBars)
        let hoverPosition = hoverProgress * geometryWidth
        return abs(barPosition - hoverPosition) < 20
    }
    
    var body: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        isPlayed ? Color.primary : Color.primary.opacity(0.3),
                        isPlayed ? Color.primary.opacity(0.8) : Color.primary.opacity(0.2)
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(
                width: max((geometryWidth / CGFloat(totalBars)) - 0.5, 1),
                height: max(CGFloat(sample) * 24, 2)
            )
            .scaleEffect(y: isHovering && isNearHover ? 1.15 : 1.0)
            .animation(.interpolatingSpring(stiffness: 300, damping: 15), value: isHovering && isNearHover)
    }
}

// MARK: - Reusable Components

private struct CircleIconButton: View {
    let icon: String
    let action: () -> Void
    var fillOpacity: Double = 0.06
    var iconFont: Font = .system(size: 14, weight: .semibold)

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color.primary.opacity(fillOpacity))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: icon)
                        .font(iconFont)
                        .foregroundStyle(.primary)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct AsyncCircleButton: View {
    let defaultIcon: String
    let isLoading: Bool
    let showSuccess: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color.primary.opacity(0.06))
                .frame(width: 32, height: 32)
                .overlay(
                    Group {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else if showSuccess {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.green)
                        } else {
                            Image(systemName: defaultIcon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                    }
                )
        }
        .buttonStyle(.plain)
    }
}

private struct StatusBanner: View {
    let message: String
    let isError: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundColor(isError ? .red : .green)
            Text(message)
                .font(.system(size: 14, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isError ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                .stroke(isError ? Color.red.opacity(0.2) : Color.green.opacity(0.2), lineWidth: 1)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Banner State

private enum BannerState: Equatable {
    case retranscribeSuccess
    case reEnhanceSuccess
    case retranscribeError(String)
    case reEnhanceError(String)
}

// MARK: - AudioPlayerView

struct AudioPlayerView: View {
    let url: URL
    let transcription: Transcription?
    var onInfoTap: (() -> Void)?
    @StateObject private var playerManager = AudioPlayerManager()
    @State private var isHovering = false
    @State private var isRetranscribing = false
    @State private var isReEnhancing = false
    @State private var bannerState: BannerState?
    @State private var showPromptPopover = false
    @EnvironmentObject private var engine: VoiceInkEngine
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @Environment(\.modelContext) private var modelContext

    private var isOperationInProgress: Bool {
        isRetranscribing || isReEnhancing
    }

    private var transcriptionService: AudioTranscriptionService {
        AudioTranscriptionService(modelContext: modelContext, engine: engine)
    }

    var body: some View {
        VStack(spacing: 8) {
            WaveformView(
                samples: playerManager.waveformSamples,
                currentTime: playerManager.currentTime,
                duration: playerManager.duration,
                isLoading: playerManager.isLoadingWaveform,
                onSeek: { playerManager.seek(to: $0) }
            )
            .padding(.horizontal, 10)

            HStack(spacing: 8) {
                Text(formatTime(playerManager.currentTime))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(.secondary)

                Spacer()

                HStack(spacing: 8) {
                    CircleIconButton(icon: "folder", action: showInFinder)
                        .help("Show in Finder")

                    Button(action: { playerManager.cyclePlaybackRate() }) {
                        Circle()
                            .fill(Color.primary.opacity(playerManager.playbackRate == 1.0 ? 0.06 : 0.14))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Text(playerManager.playbackRate == 1.0 ? "1×" : playerManager.playbackRate == 1.5 ? "1.5×" : "2×")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.primary)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Playback speed")

                    CircleIconButton(
                        icon: enhancementService.activePrompt?.icon ?? "sparkles",
                        action: { showPromptPopover.toggle() }
                    )
                    .opacity(enhancementService.isEnhancementEnabled ? 1.0 : 0.4)
                    .help("Select enhancement prompt")
                    .popover(isPresented: $showPromptPopover, arrowEdge: .bottom) {
                        EnhancementPromptPopover()
                            .environmentObject(enhancementService)
                    }

                    CircleIconButton(
                        icon: playerManager.isPlaying ? "pause.fill" : "play.fill",
                        action: { playerManager.isPlaying ? playerManager.pause() : playerManager.play() }
                    )
                    .scaleEffect(isHovering ? 1.05 : 1.0)
                    .onHover { hovering in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isHovering = hovering
                        }
                    }

                    AsyncCircleButton(
                        defaultIcon: "arrow.clockwise",
                        isLoading: isRetranscribing,
                        showSuccess: bannerState == .retranscribeSuccess,
                        action: retranscribeAudio
                    )
                    .disabled(isOperationInProgress)
                    .help("Retranscribe this audio")

                    if transcription != nil {
                        AsyncCircleButton(
                            defaultIcon: "wand.and.stars",
                            isLoading: isReEnhancing,
                            showSuccess: bannerState == .reEnhanceSuccess,
                            action: reEnhanceOnly
                        )
                        .disabled(isOperationInProgress || !enhancementService.isEnhancementEnabled || !enhancementService.isConfigured)
                        .opacity(enhancementService.isEnhancementEnabled && enhancementService.isConfigured ? 1.0 : 0.4)
                        .help("Re-enhance with selected prompt")
                    }

                    if let onInfoTap {
                        CircleIconButton(icon: "info.circle", action: onInfoTap)
                            .help("View details")
                    }
                }

                Spacer()

                Text(formatTime(playerManager.duration))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
        .onAppear {
            playerManager.loadAudio(from: url)
        }
        .onDisappear {
            playerManager.cleanup()
        }
        .overlay(
            VStack {
                if let state = bannerState {
                    switch state {
                    case .retranscribeSuccess:
                        StatusBanner(message: "Retranscription successful", isError: false)
                    case .reEnhanceSuccess:
                        StatusBanner(message: "Re-enhancement successful", isError: false)
                    case .retranscribeError(let message):
                        StatusBanner(message: message.isEmpty ? "Retranscription failed" : message, isError: true)
                    case .reEnhanceError(let message):
                        StatusBanner(message: message.isEmpty ? "Re-enhancement failed" : message, isError: true)
                    }
                }
                Spacer()
            }
            .padding(.top, 16)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: bannerState)
        )
    }

    private func showInFinder() {
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }

    private func showTemporaryBanner(_ state: BannerState) {
        bannerState = state
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { bannerState = nil }
        }
    }

    private func reEnhanceOnly() {
        guard let transcription = transcription else { return }

        guard enhancementService.isEnhancementEnabled, enhancementService.isConfigured else {
            showTemporaryBanner(.reEnhanceError("AI Enhancement is not enabled or configured"))
            return
        }

        isReEnhancing = true
        bannerState = nil

        Task {
            do {
                let (enhancedText, enhancementDuration, promptName) = try await enhancementService.enhance(transcription.text)
                await MainActor.run {
                    transcription.enhancedText = enhancedText
                    transcription.aiEnhancementModelName = enhancementService.getAIService()?.currentModel
                    transcription.promptName = promptName
                    transcription.enhancementDuration = enhancementDuration
                    transcription.aiRequestSystemMessage = enhancementService.lastSystemMessageSent
                    transcription.aiRequestUserMessage = enhancementService.lastUserMessageSent
                    try? modelContext.save()

                    isReEnhancing = false
                    showTemporaryBanner(.reEnhanceSuccess)
                }
            } catch {
                await MainActor.run {
                    isReEnhancing = false
                    showTemporaryBanner(.reEnhanceError(error.localizedDescription))
                }
            }
        }
    }

    private func retranscribeAudio() {
        guard let currentTranscriptionModel = engine.transcriptionModelManager.currentTranscriptionModel else {
            showTemporaryBanner(.retranscribeError("No transcription model selected"))
            return
        }

        isRetranscribing = true
        bannerState = nil

        Task {
            do {
                let _ = try await transcriptionService.retranscribeAudio(from: url, using: currentTranscriptionModel)
                await MainActor.run {
                    isRetranscribing = false
                    showTemporaryBanner(.retranscribeSuccess)
                }
            } catch {
                await MainActor.run {
                    isRetranscribing = false
                    showTemporaryBanner(.retranscribeError(error.localizedDescription))
                }
            }
        }
    }
}
