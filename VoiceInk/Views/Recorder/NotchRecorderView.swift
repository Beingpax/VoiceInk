import SwiftUI

struct NotchRecorderView: View {
    @ObservedObject var whisperState: WhisperState
    @ObservedObject var recorder: Recorder
    @EnvironmentObject var windowManager: NotchWindowManager
    @State private var isHovering = false
    @State private var activePopover: ActivePopoverState = .none
    @ObservedObject private var powerModeManager = PowerModeManager.shared
    
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @AppStorage("enableAIEnhancementFeatures") private var enableAIEnhancementFeatures = false
    
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
        HStack(spacing: 12) {
            if enableAIEnhancementFeatures {
                RecorderPromptButton(
                    activePopover: $activePopover,
                    buttonSize: 22,
                    padding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
                )
            }

            RecorderPowerModeButton(
                activePopover: $activePopover,
                buttonSize: 22,
                padding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
            )

            Spacer()
        }
        .frame(width: 64)
        .padding(.leading, 16)
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
    }
    
    private var statusDisplay: some View {
        RecorderStatusDisplay(
            currentState: whisperState.recordingState,
            audioMeter: recorder.audioMeter,
            menuBarHeight: menuBarHeight
        )
        .frame(width: 70)
        .padding(.trailing, 8)
    }
    
    var body: some View {
        Group {
            if windowManager.isVisible {
                HStack(spacing: 0) {
                    leftSection
                    centerSection
                    rightSection
                }
                .frame(height: menuBarHeight)
                .background(Color.black)
                .mask {
                    NotchShape(cornerRadius: 10)
                }
                .clipped()
                .onHover { hovering in
                    isHovering = hovering
                }
                .opacity(windowManager.isVisible ? 1 : 0)
            }
        }
    }
}
