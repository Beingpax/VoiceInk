import AVFoundation
import SwiftUI

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
                    HStack(spacing: 0.5) {
                        ForEach(0..<samples.count, id: \.self) { index in
                            WaveformBar(
                                sample: samples[index],
                                isPlayed: CGFloat(index) / CGFloat(samples.count) <= CGFloat(currentTime / duration),
                                totalBars: samples.count,
                                geometryWidth: geometry.size.width,
                                isHovering: isHovering,
                                hoverProgress: hoverLocation / geometry.size.width
                            )
                        }
                    }
                    .opacity(0.6)
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 2)

                    if isHovering {
                        Text(formatTime(duration * Double(hoverLocation / geometry.size.width)))
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .foregroundColor(AppTheme.Surface.window)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(AppTheme.Waveform.hoverBubble))
                            .offset(x: max(0, min(hoverLocation - 25, geometry.size.width - 50)))
                            .offset(y: -26)

                        Rectangle()
                            .fill(AppTheme.Waveform.hoverMarker)
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
                        isPlayed ? AppTheme.Waveform.playedLower : AppTheme.Waveform.unplayedLower,
                        isPlayed ? AppTheme.Waveform.playedUpper : AppTheme.Waveform.unplayedUpper,
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
    @StateObject private var playerManager = AudioPlayerManager()
    @State private var isHovering = false
    @State private var isRetranscribing = false
    @State private var isReEnhancing = false
    @State private var operationFeedback: OperationFeedback?
    @State private var showModePopover = false
    @State private var showPromptPopover = false
    @EnvironmentObject private var engine: VoiceInkEngine
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @ObservedObject private var modeManager = ModeManager.shared
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

    private var selectedMode: ModeConfig? {
        modeManager.currentEffectiveConfiguration
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
