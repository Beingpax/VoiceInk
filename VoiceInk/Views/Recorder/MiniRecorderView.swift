import SwiftUI

struct MiniRecorderView<S: RecorderStateProvider & ObservableObject>: View {
    @ObservedObject var stateProvider: S
    @ObservedObject var recorder: Recorder
    @EnvironmentObject var windowManager: MiniWindowManager
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @ObservedObject private var powerModeManager = PowerModeManager.shared
    
    @AppStorage("showLiveTextPreview") private var showLiveTextPreview = false
    @AppStorage("visualizerWaveformHeight") private var visualizerWaveformHeight = 75.0
    @AppStorage("miniRecorderWidth") private var miniRecorderWidth = 420.0
    @AppStorage("miniRecorderHeight") private var miniRecorderHeight = 180.0
    
    // New Aesthetics Storage
    @AppStorage("miniRecorderPlacement") private var miniRecorderPlacement = "bottom"
    @AppStorage("miniRecorderXOffset") private var miniRecorderXOffset = 0.0
    @AppStorage("miniRecorderYOffset") private var miniRecorderYOffset = 0.0
    @AppStorage("miniRecorderOpacity") private var miniRecorderOpacity = 0.95
    @AppStorage("visualizerMovementType") private var visualizerMovementType = "alien"
    @AppStorage("visualizerLineTheme") private var visualizerLineTheme = "cyber"
    @AppStorage("superchargeDynamicHUDIsland") private var dynamicHUDEnabled = false
    @AppStorage("superchargeDragToTarget") private var dragToTargetEnabled = false
    @AppStorage("superchargeTactileHapticScrubbing") private var hapticScrubbingEnabled = false
    @AppStorage("speedMode") private var speedMode = false

    @State private var showVoiceMenu = false

    // true when live transcript is streaming in during recording
    private var hasLiveTranscript: Bool {
        showLiveTextPreview
            && stateProvider.recordingState == .recording
            && !stateProvider.partialTranscript.isEmpty
    }

    private var activeModelSupportsStreaming: Bool {
        if let engine = stateProvider as? VoiceInkEngine,
           let model = engine.transcriptionModelManager.currentTranscriptionModel {
            return model.supportsStreaming
        }
        return false
    }

    private var activeModelDisplayName: String {
        if let engine = stateProvider as? VoiceInkEngine,
           let model = engine.transcriptionModelManager.currentTranscriptionModel {
            return model.displayName
        }
        return "Speechmatics"
    }

    private var activeEnhancementModelDisplayName: String? {
        guard enhancementService.isEnhancementEnabled,
              let aiService = enhancementService.getAIService() else {
            return nil
        }
        
        let provider = aiService.selectedProvider
        let model = aiService.currentModel
        
        if provider == .groq {
            return "Groq"
        }
        
        let lowerModel = model.lowercased()
        
        // 1. For GPT-4o-120B (or any model containing "120b"), just use transcribe provider speech -> omit the enhancement part
        if lowerModel.contains("120b") {
            return nil
        }
        
        // 2. Mattox — just the enhanced provider
        if lowerModel.contains("mattox") {
            return provider.rawValue
        }
        
        // 3. For other models under OpenAI provider, or if the model starts with "gpt-", display the provider name "OpenAI" instead of "gpt-4o" etc.
        if provider == .openAI || lowerModel.hasPrefix("gpt-") {
            return "OpenAI"
        }
        
        // Default: display the model name or provider name
        return model
    }

    // Drag-to-Target State
    @State private var dragOffset = CGSize.zero
    @State private var isDraggingToTarget = false
    @State private var activeTargetZone: String? = nil // "clipboard", "app", "log"

    private var dynamicWidth: CGFloat {
        let baseWidth = CGFloat(miniRecorderWidth)
        guard dynamicHUDEnabled else { return baseWidth }
        
        switch stateProvider.recordingState {
        case .idle, .starting:
            return baseWidth * 0.88
        case .recording:
            return baseWidth * 1.05
        case .transcribing, .enhancing, .busy:
            return baseWidth * 0.96
        }
    }
    
    private var dynamicHeight: CGFloat {
        let baseHeight = CGFloat(miniRecorderHeight)
        guard dynamicHUDEnabled else { return baseHeight }
        
        switch stateProvider.recordingState {
        case .idle, .starting:
            return baseHeight * 0.82
        case .recording:
            return baseHeight * 1.05
        case .transcribing, .enhancing, .busy:
            return baseHeight * 0.9
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                isDraggingToTarget = true
                dragOffset = value.translation
                
                let hudWidth = CGFloat(miniRecorderWidth)
                let dragX = value.location.x
                
                let oldZone = activeTargetZone
                if dragX < hudWidth * 0.33 {
                    activeTargetZone = "clipboard"
                } else if dragX > hudWidth * 0.66 {
                    activeTargetZone = "log"
                } else {
                    activeTargetZone = "app"
                }
                
                if oldZone != activeTargetZone && hapticScrubbingEnabled {
                    #if canImport(AppKit)
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                    #endif
                }
            }
            .onEnded { value in
                let text = stateProvider.partialTranscript.isEmpty ? "No active transcription to drop" : stateProvider.partialTranscript
                
                switch activeTargetZone {
                case "clipboard":
                    let _ = ClipboardManager.copyToClipboard(text)
                case "app":
                    CursorPaster.pasteAtCursor(text)
                case "log":
                    let _ = ClipboardManager.setClipboard(text)
                default:
                    break
                }
                
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    isDraggingToTarget = false
                    dragOffset = .zero
                    activeTargetZone = nil
                }
            }
    }

    var body: some View {
        if windowManager.isVisible {
            ZStack(alignment: .bottomLeading) {
                VStack(spacing: 0) {
                    // Drag to Target Handle
                    if dragToTargetEnabled {
                        HStack {
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: "hand.and.arrow.all")
                                    .font(.system(size: 8))
                                Text("DRAG TO TARGET")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                            }
                            .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.4))
                            .padding(.vertical, 4)
                            Spacer()
                        }
                        .background(Color.black.opacity(0.03))
                        .contentShape(Rectangle())
                        .gesture(dragGesture)
                    }

                    // 1. Waveform / Speed Mode Area
                    if speedMode {
                        // Speed Mode: minimal recording indicator — zero animation overhead
                        SpeedModeIndicator(state: stateProvider.recordingState)
                            .frame(maxHeight: .infinity)
                            .padding(.top, 10)
                    } else {
                        ZStack {
                            // Left decorative vertical Japanese label
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("•")
                                    Text("音")
                                    Text("声")
                                    Text("解")
                                    Text("析")
                                    Text("•")
                                }
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.12))
                                .padding(.leading, 12)
                                Spacer()
                            }
                            
                            // Top right decorative Japanese label
                            VStack {
                                HStack {
                                    Spacer()
                                    Text("ライブ •")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.12))
                                        .padding(.top, 10)
                                        .padding(.trailing, 16)
                                }
                                Spacer()
                            }

                            // Right decorative vertical Japanese label
                            HStack {
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("•")
                                    Text("解")
                                    Text("析")
                                    Text("中")
                                    Text("•")
                                }
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.12))
                                .padding(.trailing, 12)
                            }

                            // The actual waveform visualizer
                            RecorderStatusDisplay(
                                currentState: stateProvider.recordingState,
                                audioMeter: recorder.audioMeter
                            )
                            .frame(height: CGFloat(visualizerWaveformHeight))
                            .padding(.horizontal, 24)
                        }
                        .frame(maxHeight: .infinity)
                        .padding(.top, 10)
                    }

                    // 2. Live Transcript Section (scrolls under the waveform)
                    if hasLiveTranscript {
                        LiveTranscriptView(
                            text: stateProvider.partialTranscript,
                            textColor: Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.8)
                        )
                        .frame(height: 48)
                        .padding(.bottom, 6)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else {
                        Spacer(minLength: 6)
                    }

                    // 3. Bottom Status Bar
                    bottomStatusBar
                }
                .frame(width: dynamicWidth, height: speedMode ? 80 : dynamicHeight)
                .background(
                    speedMode
                        ? AnyShapeStyle(Color(red: 0.92, green: 0.93, blue: 0.96).opacity(miniRecorderOpacity))
                        : AnyShapeStyle(LinearGradient(
                            colors: [Color(red: 0.89, green: 0.90, blue: 0.94).opacity(miniRecorderOpacity), Color(red: 0.92, green: 0.93, blue: 0.96).opacity(miniRecorderOpacity)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                )
                .clipShape(RoundedRectangle(cornerRadius: speedMode ? 10 : 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: speedMode ? 10 : 16, style: .continuous)
                        .stroke(Color.white.opacity(0.85 * miniRecorderOpacity), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(speedMode ? 0.06 : 0.14 * miniRecorderOpacity), radius: speedMode ? 8 : 24, x: 0, y: speedMode ? 4 : 12)
                .animation(speedMode ? nil : .easeOut(duration: 0.15), value: hasLiveTranscript)
                .animation(speedMode ? nil : .easeOut(duration: 0.15), value: stateProvider.recordingState)
                
                // Drag-to-Target overlay
                if isDraggingToTarget {
                    HStack(spacing: 12) {
                        DragTargetZone(
                            title: "Clipboard",
                            icon: "doc.on.clipboard",
                            isActive: activeTargetZone == "clipboard",
                            color: Color.blue
                        )
                        DragTargetZone(
                            title: "Active App",
                            icon: "arrow.up.forward.app",
                            isActive: activeTargetZone == "app",
                            color: Color.purple
                        )
                        DragTargetZone(
                            title: "Save Log",
                            icon: "doc.text",
                            isActive: activeTargetZone == "log",
                            color: Color.orange
                        )
                    }
                    .padding(16)
                    .background(Color.black.opacity(0.85))
                    .cornerRadius(16)
                    .frame(width: dynamicWidth, height: dynamicHeight)
                    .transition(.opacity)
                }
                
                // 4. Custom Overlay Dropdown Popover (Flawless Mouse Clicks on Non-Activating Panels)
                if showVoiceMenu {
                    voiceMenuOverlay
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .onAppear {
                autoToggleLivePreviewIfNeeded()
            }
            .onChange(of: stateProvider.recordingState) { newState in
                if newState == .recording {
                    autoToggleLivePreviewIfNeeded()
                }
            }
            // Dynamic window frame observer triggers
            .onChange(of: miniRecorderWidth) { _ in windowManager.updateWindowMetrics() }
            .onChange(of: miniRecorderHeight) { _ in windowManager.updateWindowMetrics() }
            .onChange(of: miniRecorderPlacement) { _ in windowManager.updateWindowMetrics() }
            .onChange(of: miniRecorderXOffset) { _ in windowManager.updateWindowMetrics() }
            .onChange(of: miniRecorderYOffset) { _ in windowManager.updateWindowMetrics() }
        }
    }

    @ViewBuilder
    private var bottomStatusBar: some View {
        Divider()
            .background(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.08))
        
        HStack {
            HStack(spacing: 8) {
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                        showVoiceMenu.toggle()
                    }
                }) {
                    voiceMenuLabel
                }
                .buttonStyle(PlainButtonStyle())
                
                Divider()
                    .frame(height: 12)
                    .background(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.12))
                
                HStack(spacing: 4) {
                    Image(systemName: "circle.grid.2x1.fill")
                        .font(.system(size: 8))
                        .foregroundColor(Color(red: 0.54, green: 0.12, blue: 0.92).opacity(0.8))
                    Text(activeModelDisplayName)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.85))
                    
                    if let enhancementName = activeEnhancementModelDisplayName {
                        Text("+")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.4))
                        Image(systemName: "sparkles")
                            .font(.system(size: 8))
                            .foregroundColor(Color(red: 1.0, green: 0.416, blue: 0.0))
                        Text(enhancementName)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color(red: 1.0, green: 0.416, blue: 0.0))
                    }
                    
                    Text("音声解析")
                        .font(.system(size: 8, weight: .regular))
                        .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.4))
                }
            }
            
            Spacer()
            
            Button(action: {
                showLiveTextPreview.toggle()
            }) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(showLiveTextPreview ? Color(red: 0.54, green: 0.12, blue: 0.92) : Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.3))
                        .frame(width: 4, height: 4)
                        .shadow(color: showLiveTextPreview ? Color(red: 0.54, green: 0.12, blue: 0.92).opacity(0.8) : Color.clear, radius: 3)
                    Text("Live")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(showLiveTextPreview ? Color(red: 0.22, green: 0.24, blue: 0.35) : Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.5))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(showLiveTextPreview ? Color.white.opacity(0.6) : Color.white.opacity(0.3))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(showLiveTextPreview ? Color(red: 0.54, green: 0.12, blue: 0.92).opacity(0.3) : Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.12), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.25 * miniRecorderOpacity))
    }

    @ViewBuilder
    private var voiceMenuOverlay: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                    showVoiceMenu = false
                }
            }
        
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                enhancementService.isEnhancementEnabled.toggle()
            }) {
                HStack {
                    Image(systemName: enhancementService.isEnhancementEnabled ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(enhancementService.isEnhancementEnabled ? Color(red: 0.54, green: 0.12, blue: 0.92) : .secondary)
                    Text("AI Enhancement")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35))
                    Spacer()
                }
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if enhancementService.isEnhancementEnabled {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Prompts")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.5))
                        .padding(.leading, 2)
                    
                    ForEach(enhancementService.allPrompts) { prompt in
                        Button(action: {
                            enhancementService.selectedPromptId = prompt.id
                        }) {
                            HStack {
                                Image(systemName: prompt.icon)
                                    .font(.system(size: 9))
                                    .foregroundColor(enhancementService.selectedPromptId == prompt.id ? Color(red: 0.54, green: 0.12, blue: 0.92) : .secondary)
                                    .frame(width: 12)
                                Text(prompt.title)
                                    .font(.system(size: 9, weight: enhancementService.selectedPromptId == prompt.id ? .bold : .medium))
                                    .foregroundColor(enhancementService.selectedPromptId == prompt.id ? Color(red: 0.22, green: 0.24, blue: 0.35) : Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.75))
                                Spacer()
                                if enhancementService.selectedPromptId == prompt.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundColor(Color(red: 0.54, green: 0.12, blue: 0.92))
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(enhancementService.selectedPromptId == prompt.id ? Color(red: 0.54, green: 0.12, blue: 0.92).opacity(0.08) : Color.clear)
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 12)
            }
            
            Divider()
                .background(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.1))
            
            VStack(alignment: .leading, spacing: 3) {
                Text("Power Modes")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.5))
                    .padding(.leading, 2)
                
                ForEach(powerModeManager.configurations) { config in
                    Button(action: {
                        Task {
                            powerModeManager.setActiveConfiguration(config)
                            await PowerModeSessionManager.shared.beginSession(with: config)
                        }
                    }) {
                        HStack {
                            Text(config.emoji)
                                .font(.system(size: 9))
                            Text(config.name)
                                .font(.system(size: 9, weight: powerModeManager.activeConfiguration?.id == config.id ? .bold : .medium))
                                .foregroundColor(powerModeManager.activeConfiguration?.id == config.id ? Color(red: 0.22, green: 0.24, blue: 0.35) : Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.75))
                            Spacer()
                            if powerModeManager.activeConfiguration?.id == config.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundColor(Color(red: 0.54, green: 0.12, blue: 0.92))
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(powerModeManager.activeConfiguration?.id == config.id ? Color(red: 0.54, green: 0.12, blue: 0.92).opacity(0.08) : Color.clear)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                
                if powerModeManager.activeConfiguration != nil {
                    Button(action: {
                        Task {
                            await PowerModeSessionManager.shared.endSession()
                            powerModeManager.setActiveConfiguration(nil)
                        }
                    }) {
                        HStack {
                            Image(systemName: "power")
                                .font(.system(size: 9))
                                .foregroundColor(.red)
                            Text("Turn Off Power Mode")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.red)
                            Spacer()
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.05))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
        }
        .padding(8)
        .frame(width: 190)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .background(Color.white.opacity(0.95))
        )
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 6)
        .padding(.leading, 12)
        .padding(.bottom, 40)
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomLeading)))
    }

    @ViewBuilder
    private var voiceMenuLabel: some View {
        HStack(spacing: 5) {
            BreathingBlueDot()
            Text("VOICE")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35))
            
            if let activeName = powerModeManager.activeConfiguration?.name {
                Text("•")
                    .font(.system(size: 8))
                    .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.4))
                Text(activeName.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.54, green: 0.12, blue: 0.92))
            } else if enhancementService.isEnhancementEnabled, let promptName = enhancementService.activePrompt?.title {
                Text("•")
                    .font(.system(size: 8))
                    .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.4))
                Text(promptName.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.54, green: 0.12, blue: 0.92))
            }
            
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.4))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.55))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.12), lineWidth: 1)
        )
    }
    private func autoToggleLivePreviewIfNeeded() {
        if activeModelSupportsStreaming {
            showLiveTextPreview = true
        }
    }
}

// Glowing status dot helper view (Non-blinking/Static)
struct BreathingBlueDot: View {
    var body: some View {
        Circle()
            .fill(Color(red: 0.28, green: 0.58, blue: 0.95)) // Glowing white-blue
            .frame(width: 5, height: 5)
            .overlay(
                Circle()
                    .stroke(Color(red: 0.54, green: 0.12, blue: 0.92).opacity(0.6), lineWidth: 1) // Glowing electric purple aura
            )
    }
}

struct DragTargetZone: View {
    let title: String
    let icon: String
    let isActive: Bool
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(isActive ? .white : color.opacity(0.8))
                .scaleEffect(isActive ? 1.25 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isActive)
            
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(isActive ? .white : .white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isActive ? color : Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isActive ? Color.white.opacity(0.5) : color.opacity(0.3), lineWidth: 1.5)
                )
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isActive)
    }
}
