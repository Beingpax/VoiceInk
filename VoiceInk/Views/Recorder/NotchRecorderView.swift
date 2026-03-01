import SwiftUI

struct NotchRecorderView: View {
    @ObservedObject var engine: VoiceInkEngine
    @ObservedObject var recorder: Recorder
    @EnvironmentObject var windowManager: NotchWindowManager
    @State private var isHovering = false
    @State private var activePopover: ActivePopoverState = .none
    @ObservedObject private var powerModeManager = PowerModeManager.shared
    
    @EnvironmentObject private var enhancementService: AIEnhancementService
    
    private var menuBarHeight: CGFloat {
        if let screen = NSScreen.main {
            if screen.safeAreaInsets.top > 0 {
                return screen.safeAreaInsets.top
            }
            return NSApplication.shared.mainMenu?.menuBarHeight ?? NSStatusBar.system.thickness
        }
        return NSStatusBar.system.thickness
    }
    
    private var exactNotchWidth: CGFloat {
        if let screen = NSScreen.main {
            if screen.safeAreaInsets.left > 0 {
                return screen.safeAreaInsets.left * 2
            }
            return 200
        }
        return 200
    }
    
    private var leftSection: some View {
        HStack(spacing: 16) {
            RecorderPromptButton(
                activePopover: $activePopover,
                buttonSize: 22,
                padding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
            )

            RecorderPowerModeButton(
                activePopover: $activePopover,
                buttonSize: 22,
                padding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
            )

            Spacer()
        }
        .frame(width: 64)
        .padding(.leading, 16)
        .padding(.leading, 4)
    }
    
    private var centerSection: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: exactNotchWidth)
            .contentShape(Rectangle())
    }
    
    private var rightSection: some View {
        HStack(spacing: 8) {
            Spacer()
            statusDisplay
        }
        .frame(width: 64)
        .padding(.trailing, 16)
        .padding(.trailing, 4)
    }
    
    private var statusDisplay: some View {
        RecorderStatusDisplay(
            currentState: engine.recordingState,
            audioMeter: recorder.audioMeter,
            menuBarHeight: menuBarHeight
        )
        .frame(width: 70)
        .padding(.trailing, 8)
    }

    private var bottomSection: some View {
        // TimelineView polls transcript at 10Hz and controls visibility
        // Same pattern as AudioVisualizer - no forced re-renders
        TimelineView(.animation(minimumInterval: 0.1)) { context in
            let hasText = engine.recordingState == .recording && !engine.partialTranscript.isEmpty

            VStack(spacing: 0) {
                Divider()
                    .background(Color.white.opacity(0.15))

                Text(engine.partialTranscript)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 5)
            }
            .opacity(hasText ? 1 : 0)
            .frame(height: hasText ? nil : 0)
            .clipped()
        }
    }

    private var topCornerRadius: CGFloat {
        6
    }

    private var bottomCornerRadius: CGFloat {
        10
    }

    var body: some View {
        Group {
            if windowManager.isVisible {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        leftSection
                        centerSection
                        rightSection
                    }
                    .frame(height: menuBarHeight)

                    bottomSection
                }
                .background(Color.black)
                .mask {
                    NotchShape(
                        topCornerRadius: topCornerRadius,
                        bottomCornerRadius: bottomCornerRadius
                    )
                }
                .clipped()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .onHover { hovering in
                    isHovering = hovering
                }
                .opacity(windowManager.isVisible ? 1 : 0)
            }
        }
    }
}
