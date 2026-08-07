import AVFoundation
import OSLog
import SwiftUI

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
    // NSCache is thread-safe; the waveform generator runs off the main actor.
    nonisolated(unsafe) private static let cache = NSCache<NSString, NSArray>()

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
                    // Peak across the whole window, not just its first frame — otherwise the
                    // waveform is a point sample rather than an envelope and under-reports
                    // loud passages.
                    var peak: Float = 0
                    for frame in 0..<Int(buffer.frameLength) {
                        peak = max(peak, abs(channelData[frame]))
                    }
                    maxValues[sampleIndex] = peak
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

@MainActor
@Observable
final class AudioPlayerManager: NSObject, AVAudioPlayerDelegate {
    private static let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "AudioPlayerManager"
    )

    private var audioPlayer: AVAudioPlayer?

    var isPlaying = false
    var duration: TimeInterval = 0
    var waveformSamples: [Float] = []
    var isLoadingWaveform = false
    var playbackRate: Float = {
        let saved = UserDefaults.standard.float(forKey: "audioPlaybackRate")
        return saved > 0 ? saved : 1.0
    }()
    {
        didSet { UserDefaults.standard.set(playbackRate, forKey: "audioPlaybackRate") }
    }

    /// Read directly off the player rather than republished on a timer. The waveform samples this
    /// each frame from a TimelineView, so playback no longer invalidates the view tree at 10Hz.
    var currentTime: TimeInterval {
        audioPlayer?.currentTime ?? 0
    }

    /// Where playback should stop, when a trim range is active.
    var playbackLimit: TimeInterval?

    func loadAudio(from url: URL) {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.enableRate = true
            player.prepareToPlay()
            audioPlayer = player
            duration = player.duration
            isLoadingWaveform = true

            Task {
                let samples = await WaveformGenerator.generateWaveformSamples(from: url)
                self.waveformSamples = samples
                self.isLoadingWaveform = false
            }
        } catch {
            Self.logger.error("Error loading audio: \(error, privacy: .public)")
        }
    }

    func play() {
        audioPlayer?.rate = playbackRate
        audioPlayer?.play()
        isPlaying = true
    }

    func cyclePlaybackRate() {
        switch playbackRate {
        case 1.0: playbackRate = 1.5
        case 1.5: playbackRate = 2.0
        default: playbackRate = 1.0
        }
        audioPlayer?.rate = playbackRate
    }

    func pause() {
        audioPlayer?.pause()
        isPlaying = false
    }

    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = max(0, min(time, duration))
    }

    /// Called each frame while playing so a trim range can stop playback at its end.
    func enforcePlaybackLimit() {
        guard isPlaying, let limit = playbackLimit, currentTime >= limit else { return }
        pause()
    }

    func cleanup() {
        audioPlayer?.stop()
        audioPlayer?.delegate = nil
        audioPlayer = nil
        isPlaying = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.seek(to: 0)
        }
    }
}

private func formatTime(_ time: TimeInterval) -> String {
    let minutes = Int(time) / 60
    let seconds = Int(time) % 60
    return String(format: "%d:%02d", minutes, seconds)
}

/// A start/end pair in seconds. Always normalized so `start <= end`.
struct WaveformRange: Equatable {
    var start: TimeInterval
    var end: TimeInterval

    var lower: TimeInterval { min(start, end) }
    var upper: TimeInterval { max(start, end) }
    var length: TimeInterval { upper - lower }

    /// Ignore incidental drags that were really just a click-to-seek.
    var isMeaningful: Bool { length > 0.15 }
}

struct WaveformView: View {
    let samples: [Float]
    let duration: TimeInterval
    let isLoading: Bool
    let isPlaying: Bool
    /// Read per frame rather than passed as published state.
    let timeProvider: () -> TimeInterval
    var onSeek: (Double) -> Void
    @Binding var selection: WaveformRange?

    @State private var isHovering = false
    @State private var hoverLocation: CGFloat = 0
    @State private var dragAnchor: TimeInterval?

    private let barHeight: CGFloat = 24

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                if isLoading {
                    HStack(spacing: AppTheme.Spacing.s) {
                        ProgressView().controlSize(.small)
                        Text("Loading…")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // One Canvas draw instead of ~200 individual views. TimelineView only ticks
                    // while audio is actually playing.
                    TimelineView(.animation(paused: !isPlaying)) { _ in
                        Canvas { context, size in
                            draw(in: &context, size: size, playhead: timeProvider())
                        }
                    }

                    if isHovering {
                        hoverReadout(width: geometry.size.width)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(scrubGesture(width: geometry.size.width))
            .onHover { hovering in
                guard !isLoading else { return }
                withAnimation(AppTheme.Motion.quick) { isHovering = hovering }
            }
            .onContinuousHover { phase in
                guard !isLoading, case .active(let location) = phase else { return }
                hoverLocation = location.x
            }
        }
        .frame(height: 32)
        .accessibilityElement()
        .accessibilityLabel("Audio waveform")
        .accessibilityValue(Text(formatTime(timeProvider()) + " of " + formatTime(duration)))
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize, playhead: TimeInterval) {
        guard !samples.isEmpty, duration > 0 else { return }

        let barSlot = size.width / CGFloat(samples.count)
        let barWidth = max(barSlot - 0.5, 1)
        let midY = size.height / 2
        let progress = CGFloat(playhead / duration)
        let selectionRange = selection.map { ($0.lower / duration, $0.upper / duration) }

        if let selectionRange {
            let rect = CGRect(
                x: size.width * CGFloat(selectionRange.0),
                y: 0,
                width: size.width * CGFloat(selectionRange.1 - selectionRange.0),
                height: size.height
            )
            context.fill(Path(rect), with: .color(AppTheme.Accent.fill))
        }

        for (index, sample) in samples.enumerated() {
            let fraction = CGFloat(index) / CGFloat(samples.count)
            let height = max(CGFloat(sample) * barHeight, 2)
            let rect = CGRect(
                x: fraction * size.width,
                y: midY - height / 2,
                width: barWidth,
                height: height
            )

            let isPlayed = fraction <= progress
            let inSelection =
                selectionRange.map { fraction >= CGFloat($0.0) && fraction <= CGFloat($0.1) } ?? false

            let color: Color
            if inSelection {
                color = AppTheme.Accent.primary
            } else if isPlayed {
                color = AppTheme.Waveform.playedLower
            } else {
                color = AppTheme.Waveform.unplayedLower
            }

            context.fill(
                Path(roundedRect: rect, cornerRadius: barWidth / 2),
                with: .color(color.opacity(inSelection ? 0.9 : 0.6))
            )
        }

        // Playhead
        let x = progress * size.width
        context.stroke(
            Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) },
            with: .color(AppTheme.Waveform.playedLower.opacity(0.85)),
            lineWidth: 1.5
        )
    }

    private func hoverReadout(width: CGFloat) -> some View {
        let time = duration * Double(hoverLocation / max(width, 1))

        return ZStack(alignment: .leading) {
            Text(formatTime(time))
                .font(AppTheme.Typography.caption)
                .monospacedDigit()
                .foregroundStyle(AppTheme.Surface.window)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(AppTheme.Waveform.hoverBubble))
                .offset(x: max(0, min(hoverLocation - 25, width - 50)), y: -26)

            Rectangle()
                .fill(AppTheme.Waveform.hoverMarker)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                .offset(x: hoverLocation)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Gesture

    /// A click seeks. A drag of any real distance defines a trim range instead — so scrubbing and
    /// range-selection share one gesture without a modifier key.
    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isLoading, duration > 0 else { return }

                hoverLocation = value.location.x
                let time = Double(value.location.x / max(width, 1)) * duration

                if dragAnchor == nil {
                    dragAnchor = Double(value.startLocation.x / max(width, 1)) * duration
                }

                guard let anchor = dragAnchor else { return }
                let candidate = WaveformRange(start: anchor, end: time)

                if candidate.isMeaningful {
                    selection = candidate
                } else {
                    selection = nil
                    onSeek(time)
                }
            }
            .onEnded { _ in
                dragAnchor = nil
            }
    }
}

// MARK: - Reusable Components

private struct CircleIconButton: View {
    let icon: String
    let action: () -> Void
    var fill: Color = AppTheme.Surface.subtle
    var iconFont: Font = .system(size: 14, weight: .semibold)

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(fill)
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
                .fill(AppTheme.Surface.subtle)
                .frame(width: 32, height: 32)
                .overlay(
                    Group {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else if showSuccess {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppTheme.Status.success)
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

// MARK: - Operation Feedback

private enum OperationFeedback: Equatable {
    case retranscribeSuccess
    case reEnhanceSuccess
}

// MARK: - AudioPlayerView

struct AudioPlayerView: View {
    let url: URL
    let transcription: Transcription?
    var onInfoTap: (() -> Void)?
    @State private var playerManager = AudioPlayerManager()
    @State private var trimSelection: WaveformRange?
    @State private var isExportingClip = false
    @State private var isHovering = false
    @State private var isRetranscribing = false
    @State private var isReEnhancing = false
    @State private var operationFeedback: OperationFeedback?
    @State private var showModePopover = false
    @State private var showPromptPopover = false
    @Environment(VoiceInkEngine.self) private var engine
    @Environment(AIEnhancementService.self) private var enhancementService
    private let modeManager = ModeManager.shared
    @Environment(\.modelContext) private var modelContext

    private var isOperationInProgress: Bool {
        isRetranscribing || isReEnhancing
    }

    private var currentEnhancementConfiguration: EnhancementRuntimeConfiguration? {
        guard let aiService = enhancementService.getAIService() else { return nil }
        return ModeRuntimeResolver.currentEnhancementConfiguration(
            mode: selectedMode,
            enhancementService: enhancementService,
            aiService: aiService
        )
    }

    private var transcriptionService: AudioTranscriptionService {
        AudioTranscriptionService(modelContext: modelContext, engine: engine)
    }

    // MARK: - Trim

    @ViewBuilder
    private func trimBar(for range: WaveformRange) -> some View {
        HStack(spacing: AppTheme.Spacing.s) {
            Image(systemName: "selection.pin.in.out")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Accent.primary)
                .accessibilityHidden(true)

            Text(
                String(
                    format: String(localized: "%@ – %@ (%@)"),
                    formatTime(range.lower),
                    formatTime(range.upper),
                    range.length.formatTiming()
                )
            )
            .font(AppTheme.Typography.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)

            Spacer()

            Button("Play") {
                playerManager.playbackLimit = range.upper
                playerManager.seek(to: range.lower)
                playerManager.play()
            }
            .controlSize(.small)

            Button {
                exportClip(range)
            } label: {
                if isExportingClip {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Export Clip…")
                }
            }
            .controlSize(.small)
            .disabled(isExportingClip)
            .help("Export the selected audio and its transcript")

            Button {
                clearTrimSelection()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Clear selection")
            .accessibilityLabel("Clear selection")
        }
        .padding(.horizontal, AppTheme.Spacing.m)
        .padding(.vertical, AppTheme.Spacing.s)
        .background(AppCardBackground(cornerRadius: AppTheme.Radius.row))
    }

    private func clearTrimSelection() {
        withAnimation(AppTheme.Motion.quick) {
            trimSelection = nil
        }
        playerManager.playbackLimit = nil
    }

    private func exportClip(_ range: WaveformRange) {
        isExportingClip = true

        Task {
            defer { isExportingClip = false }

            do {
                try await AudioClipExporter.export(
                    source: url,
                    range: range,
                    transcriptText: transcription?.displayText
                )
            } catch AudioClipExporter.ExportError.cancelled {
                return
            } catch {
                NotificationManager.shared.showNotification(
                    title: String(localized: "Could not export clip"),
                    type: .error
                )
            }
        }
    }

    private var selectedMode: ModeConfig? {
        modeManager.currentEffectiveConfiguration
    }

    var body: some View {
        VStack(spacing: 8) {
            WaveformView(
                samples: playerManager.waveformSamples,
                duration: playerManager.duration,
                isLoading: playerManager.isLoadingWaveform,
                isPlaying: playerManager.isPlaying,
                timeProvider: { playerManager.currentTime },
                onSeek: { playerManager.seek(to: $0) },
                selection: $trimSelection
            )
            .padding(.horizontal, 10)

            if let trimSelection, trimSelection.isMeaningful {
                trimBar(for: trimSelection)
                    .padding(.horizontal, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack(spacing: 8) {
                TimelineView(.animation(paused: !playerManager.isPlaying)) { _ in
                    Text(formatTime(playerManager.currentTime))
                        .font(AppTheme.Typography.captionEmphasized)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    CircleIconButton(icon: "folder", action: showInFinder)
                        .help("Show in Finder")

                    Button(action: { playerManager.cyclePlaybackRate() }) {
                        Circle()
                            .fill(
                                playerManager.playbackRate == 1.0
                                    ? AppTheme.Surface.subtle : AppTheme.Surface.controlActive
                            )
                            .frame(width: 32, height: 32)
                            .overlay(
                                Text(
                                    playerManager.playbackRate == 1.0
                                        ? "1×" : playerManager.playbackRate == 1.5 ? "1.5×" : "2×"
                                )
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.primary)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Playback speed")

                    modeSelectorButton

                    CircleIconButton(
                        icon: playerManager.isPlaying ? "pause.fill" : "play.fill",
                        action: {
                            if playerManager.isPlaying {
                                playerManager.pause()
                            } else {
                                // Plain playback ignores any trim range.
                                playerManager.playbackLimit = nil
                                playerManager.play()
                            }
                        }
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
                        showSuccess: operationFeedback == .retranscribeSuccess,
                        action: retranscribeAudio
                    )
                    .disabled(isOperationInProgress)
                    .help("Retranscribe this audio")

                    if transcription != nil {
                        AsyncCircleButton(
                            defaultIcon: "wand.and.stars",
                            isLoading: isReEnhancing,
                            showSuccess: operationFeedback == .reEnhanceSuccess,
                            action: { showPromptPopover.toggle() }
                        )
                        .disabled(isOperationInProgress)
                        .help("Re-enhance with selected prompt")
                        .popover(isPresented: $showPromptPopover, arrowEdge: .bottom) {
                            promptSelectionPopover
                        }
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
        // Only runs while a trim range is actually being auditioned, and is cancelled with the
        // view — no free-running timer.
        .task(id: playbackLimitWatchKey) {
            guard playerManager.isPlaying, playerManager.playbackLimit != nil else { return }

            while !Task.isCancelled, playerManager.isPlaying {
                playerManager.enforcePlaybackLimit()
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private var playbackLimitWatchKey: String {
        "\(playerManager.isPlaying)|\(playerManager.playbackLimit ?? -1)"
    }

    private func showInFinder() {
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }

    private var modeSelectorButton: some View {
        Button {
            showModePopover.toggle()
        } label: {
            Circle()
                .fill(selectedMode == nil ? AppTheme.Surface.subtle : AppTheme.Surface.controlActive)
                .frame(width: 32, height: 32)
                .overlay {
                    if let selectedMode {
                        ModeIconView(icon: selectedMode.icon, size: selectedMode.icon.kind == .emoji ? 14 : 12)
                    } else {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary.opacity(0.6))
                    }
                }
        }
        .buttonStyle(.plain)
        .opacity(selectedMode == nil ? 0.4 : 1.0)
        .help(selectedMode.map { "Mode: \($0.name)" } ?? "Select mode")
        .popover(isPresented: $showModePopover, arrowEdge: .bottom) {
            ModePopover(selectedModeId: selectedMode?.id) { mode in
                selectMode(mode)
            }
        }
    }

    private func selectMode(_ mode: ModeConfig) {
        modeManager.setActiveConfiguration(mode)
        showModePopover = false
    }

    private var promptSelectionPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Prompt")
                .font(.headline)
                .foregroundColor(.white.opacity(0.9))
                .padding(.horizontal)
                .padding(.top, 8)

            Divider()
                .background(Color.white.opacity(0.1))

            ScrollView {
                let prompts = enhancementService.allPrompts
                let customPromptsUnavailable =
                    currentEnhancementConfiguration?.provider == .voiceInkRefine
                VStack(alignment: .leading, spacing: 4) {
                    if customPromptsUnavailable {
                        Text(
                            "Custom prompts aren't available with VoiceInk Refine. Select a Mode that uses another AI provider."
                        )
                        .foregroundColor(.white.opacity(0.7))
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 6)
                    }

                    if prompts.isEmpty {
                        Text("No Prompts Available")
                            .foregroundColor(.white.opacity(0.8))
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    } else {
                        ForEach(prompts) { prompt in
                            EnhancementPromptRow(
                                prompt: prompt,
                                isSelected: currentEnhancementConfiguration?.prompt?.id == prompt.id,
                                isDisabled: customPromptsUnavailable,
                                action: {
                                    selectPromptForReEnhancement(prompt)
                                }
                            )
                            .disabled(customPromptsUnavailable)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .frame(width: 220)
        .frame(maxHeight: 340)
        .padding(.vertical, 8)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }

    private func selectPromptForReEnhancement(_ prompt: CustomPrompt) {
        showPromptPopover = false
        reEnhanceOnly(prompt: prompt)
    }

    private func showSuccessFeedback(_ feedback: OperationFeedback, title: String) {
        operationFeedback = feedback
        NotificationManager.shared.showNotification(title: title, type: .success, duration: 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if operationFeedback == feedback {
                withAnimation { operationFeedback = nil }
            }
        }
    }

    private func showErrorNotification(_ title: String) {
        NotificationManager.shared.showNotification(title: title, type: .error, duration: 3.0)
    }

    private func reEnhanceOnly(prompt selectedPrompt: CustomPrompt) {
        guard let transcription = transcription else { return }

        guard let baseEnhancementConfiguration = currentEnhancementConfiguration else {
            showErrorNotification(String(localized: "AI Enhancement is not enabled or configured"))
            return
        }

        let enhancementConfiguration = baseEnhancementConfiguration.replacingPrompt(selectedPrompt)

        isReEnhancing = true
        operationFeedback = nil

        Task {
            do {
                let enhancementResult = try await enhancementService.enhance(
                    transcription.text,
                    configuration: enhancementConfiguration
                )
                await MainActor.run {
                    transcription.enhancedText = enhancementResult.text
                    transcription.aiEnhancementModelName =
                        enhancementConfiguration.modelName ?? enhancementConfiguration.provider?.defaultModel
                    transcription.promptName = enhancementResult.promptName
                    transcription.enhancementDuration = enhancementResult.duration
                    transcription.aiRequestSystemMessage = enhancementResult.systemMessage
                    transcription.aiRequestUserMessage = enhancementResult.userMessage
                    try? modelContext.save()

                    isReEnhancing = false
                    showSuccessFeedback(.reEnhanceSuccess, title: String(localized: "Re-enhancement successful"))
                }
            } catch {
                let errorDescription = EnhancementFailureFormatter.description(for: error)
                let failureMessage = EnhancementFailureFormatter.reEnhancementMessage(
                    description: errorDescription
                )
                await MainActor.run {
                    isReEnhancing = false
                    showErrorNotification(failureMessage)
                }
            }
        }
    }

    private func retranscribeAudio() {
        guard let selectedMode else {
            showErrorNotification(String(localized: "No mode selected"))
            return
        }

        guard
            let transcriptionConfiguration = ModeRuntimeResolver.transcriptionConfiguration(
                mode: selectedMode,
                transcriptionModelManager: engine.transcriptionModelManager
            )
        else {
            showErrorNotification(String(localized: "No transcription model selected"))
            return
        }

        isRetranscribing = true
        operationFeedback = nil

        Task {
            do {
                let result = try await transcriptionService.retranscribeAudio(
                    from: url,
                    using: transcriptionConfiguration.model,
                    mode: selectedMode
                )
                await MainActor.run {
                    isRetranscribing = false
                    if let enhancementFailure = result.enhancementFailure {
                        NotificationManager.shared.showNotification(
                            title: EnhancementFailureFormatter.transcriptionSavedMessage(
                                description: enhancementFailure
                            ),
                            type: .warning
                        )
                    } else {
                        showSuccessFeedback(
                            .retranscribeSuccess,
                            title: String(localized: "Retranscription successful")
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    isRetranscribing = false
                    showErrorNotification(
                        error.localizedDescription.isEmpty
                            ? String(localized: "Retranscription failed") : error.localizedDescription)
                }
            }
        }
    }
}
