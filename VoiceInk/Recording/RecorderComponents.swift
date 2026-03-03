import SwiftUI

// MARK: - Shared Popover State
enum ActivePopoverState {
    case none
    case enhancement
    case power
}

// MARK: - Hover Interaction Manager
class HoverInteraction: ObservableObject {
    @Published var isHovered: Bool = false

    func setHover(on: Bool) {
        if on {
            if !isHovered {
                isHovered = true
            }
        } else {
            isHovered = false
        }
    }
}

// MARK: - Generic Toggle Button Component
struct RecorderToggleButton: View {
    let isEnabled: Bool
    let icon: String
    let color: Color
    let disabled: Bool
    let action: () -> Void
    
    init(isEnabled: Bool, icon: String, color: Color, disabled: Bool = false, action: @escaping () -> Void) {
        self.isEnabled = isEnabled
        self.icon = icon
        self.color = color
        self.disabled = disabled
        self.action = action
    }
    
    private var isEmoji: Bool {
        return !icon.contains(".") && !icon.contains("-") && icon.unicodeScalars.contains { !$0.isASCII }
    }
    
    var body: some View {
        Button(action: action) {
            Group {
                if isEmoji {
                    Text(icon)
                        .font(.system(size: 14))
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                }
            }
            .foregroundColor(disabled ? .white.opacity(0.3) : (isEnabled ? .white : .white.opacity(0.6)))
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(disabled)
    }
}

// MARK: - Generic Record Button Component
struct RecorderRecordButton: View {
    let isRecording: Bool
    let isProcessing: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(buttonColor)
                    .frame(width: 25, height: 25)
                
                if isProcessing {
                    ProcessingIndicator(color: .white)
                        .frame(width: 16, height: 16)
                } else if isRecording {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white)
                        .frame(width: 9, height: 9)
                } else {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 9, height: 9)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isProcessing)
    }
    
    private var buttonColor: Color {
        if isProcessing {
            return Color(red: 0.4, green: 0.4, blue: 0.45)
        } else if isRecording {
            return .red
        } else {
            return Color(red: 0.3, green: 0.3, blue: 0.35)
        }
    }
}

// MARK: - Processing Indicator Component
struct ProcessingIndicator: View {
    @State private var rotation: Double = 0
    let color: Color
    
    var body: some View {
        Circle()
            .trim(from: 0.1, to: 0.9)
            .stroke(color, lineWidth: 1.7)
            .frame(width: 14, height: 14)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

// MARK: - Progress Animation Component
struct ProgressAnimation: View {
    let color: Color
    let animationSpeed: Double

    private let dotCount = 5
    private let dotSize: CGFloat = 3
    private let dotSpacing: CGFloat = 2

    @State private var currentDot = 0
    @State private var timer: Timer?

    init(color: Color = .white, animationSpeed: Double = 0.3) {
        self.color = color
        self.animationSpeed = animationSpeed
    }

    var body: some View {
        HStack(spacing: dotSpacing) {
            ForEach(0..<dotCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: dotSize / 2)
                    .fill(color.opacity(index <= currentDot ? 0.85 : 0.25))
                    .frame(width: dotSize, height: dotSize)
            }
        }
        .onAppear {
            startAnimation()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private func startAnimation() {
        timer?.invalidate()
        currentDot = 0
        timer = Timer.scheduledTimer(withTimeInterval: animationSpeed, repeats: true) { _ in
            currentDot = (currentDot + 1) % (dotCount + 2)
            if currentDot > dotCount { currentDot = -1 }
        }
    }
}

// MARK: - Prompt Button Component
struct RecorderPromptButton: View {
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @Binding var activePopover: ActivePopoverState
    let buttonSize: CGFloat
    let padding: EdgeInsets
    @State private var isHoveringEnhancement: Bool = false
    @State private var isHoveringEnhancementPopover: Bool = false
    @State private var enhancementDismissWorkItem: DispatchWorkItem?

    init(activePopover: Binding<ActivePopoverState>, buttonSize: CGFloat = 28, padding: EdgeInsets = EdgeInsets(top: 0, leading: 7, bottom: 0, trailing: 0)) {
        self._activePopover = activePopover
        self.buttonSize = buttonSize
        self.padding = padding
    }
    
    var body: some View {
        RecorderToggleButton(
            isEnabled: enhancementService.isEnhancementEnabled,
            icon: enhancementService.activePrompt?.icon ?? enhancementService.allPrompts.first(where: { $0.id == PredefinedPrompts.defaultPromptId })?.icon ?? "checkmark.seal.fill",
            color: .blue,
            disabled: false
        ) {
            if enhancementService.isEnhancementEnabled {
                activePopover = activePopover == .enhancement ? .none : .enhancement
            } else {
                enhancementService.isEnhancementEnabled = true
            }
        }
        .frame(width: buttonSize)
        .padding(padding)
        .onHover {
            isHoveringEnhancement = $0
            syncEnhancementPopoverVisibility()
        }
        .popover(isPresented: .constant(activePopover == .enhancement), arrowEdge: .bottom) {
            EnhancementPromptPopover()
                .environmentObject(enhancementService)
                .onHover {
                    isHoveringEnhancementPopover = $0
                    syncEnhancementPopoverVisibility()
                }
        }
    }

    private func syncEnhancementPopoverVisibility() {
        let shouldShow = isHoveringEnhancement || isHoveringEnhancementPopover
        if shouldShow {
            enhancementDismissWorkItem?.cancel()
            enhancementDismissWorkItem = nil
            activePopover = .enhancement
        } else {
            enhancementDismissWorkItem?.cancel()
            let work = DispatchWorkItem { [activePopoverBinding = $activePopover] in
                if activePopoverBinding.wrappedValue == .enhancement {
                    activePopoverBinding.wrappedValue = .none
                }
            }
            enhancementDismissWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }
}

// MARK: - Power Mode Button Component
struct RecorderPowerModeButton: View {
    @ObservedObject private var powerModeManager = PowerModeManager.shared
    @Binding var activePopover: ActivePopoverState
    let buttonSize: CGFloat
    let padding: EdgeInsets
    @State private var isHoveringPower: Bool = false
    @State private var isHoveringPowerPopover: Bool = false
    @State private var powerDismissWorkItem: DispatchWorkItem?
    
    init(activePopover: Binding<ActivePopoverState>, buttonSize: CGFloat = 28, padding: EdgeInsets = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 7)) {
        self._activePopover = activePopover
        self.buttonSize = buttonSize
        self.padding = padding
    }
    
    var body: some View {
        RecorderToggleButton(
            isEnabled: !powerModeManager.enabledConfigurations.isEmpty,
            icon: powerModeManager.enabledConfigurations.isEmpty ? "✨" : (powerModeManager.currentActiveConfiguration?.emoji ?? "✨"),
            color: .orange,
            disabled: powerModeManager.enabledConfigurations.isEmpty
        ) {
            activePopover = activePopover == .power ? .none : .power
        }
        .frame(width: buttonSize)
        .padding(padding)
        .onHover {
            isHoveringPower = $0
            syncPowerPopoverVisibility()
        }
        .popover(isPresented: .constant(activePopover == .power), arrowEdge: .bottom) {
            PowerModePopover()
                .onHover {
                    isHoveringPowerPopover = $0
                    syncPowerPopoverVisibility()
                }
        }
    }

    private func syncPowerPopoverVisibility() {
        let shouldShow = isHoveringPower || isHoveringPowerPopover
        if shouldShow {
            powerDismissWorkItem?.cancel()
            powerDismissWorkItem = nil
            activePopover = .power
        } else {
            powerDismissWorkItem?.cancel()
            let work = DispatchWorkItem { [activePopoverBinding = $activePopover] in
                if activePopoverBinding.wrappedValue == .power {
                    activePopoverBinding.wrappedValue = .none
                }
            }
            powerDismissWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }
}

// MARK: - Status Display Component
struct RecorderStatusDisplay: View {
    let currentState: RecordingState
    let audioMeter: AudioMeter
    let menuBarHeight: CGFloat?

    init(currentState: RecordingState, audioMeter: AudioMeter, menuBarHeight: CGFloat? = nil) {
        self.currentState = currentState
        self.audioMeter = audioMeter
        self.menuBarHeight = menuBarHeight
    }

    var body: some View {
        Group {
            if currentState == .enhancing {
                ProcessingStatusDisplay(mode: .enhancing, color: .white)
                    .transition(.opacity)
            } else if currentState == .transcribing {
                ProcessingStatusDisplay(mode: .transcribing, color: .white)
                    .transition(.opacity)
            } else if currentState == .recording {
                AudioVisualizer(
                    audioMeter: audioMeter,
                    color: .white,
                    isActive: currentState == .recording
                )
                .scaleEffect(y: menuBarHeight != nil ? min(1.0, (menuBarHeight! - 8) / 25) : 1.0, anchor: .center)
                .transition(.opacity)
            } else {
                StaticVisualizer(color: .white)
                    .scaleEffect(y: menuBarHeight != nil ? min(1.0, (menuBarHeight! - 8) / 25) : 1.0, anchor: .center)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: currentState)
    }
}
