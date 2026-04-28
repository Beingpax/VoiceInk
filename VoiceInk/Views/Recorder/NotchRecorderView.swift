import SwiftUI

struct NotchRecorderView<S: RecorderStateProvider & ObservableObject>: View {
    @ObservedObject var stateProvider: S
    @ObservedObject var recorder: Recorder
    @EnvironmentObject var windowManager: NotchWindowManager
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @AppStorage("showLiveTextPreview") private var showLiveTextPreview = false
    @ObservedObject private var powerModeManager = PowerModeManager.shared
    @State private var activePopover: ActivePopoverState = .none

    // MARK: - Display State

    private enum DisplayState: Equatable {
        case collapsed
        case active
        case liveText
    }

    private var displayState: DisplayState {
        switch stateProvider.recordingState {
        case .recording:
            let shouldShowLive = showLiveTextPreview && !stateProvider.partialTranscript.isEmpty
            return shouldShowLive ? .liveText : .active
        case .transcribing, .enhancing:
            return .active
        default:
            return .collapsed
        }
    }

    // MARK: - Screen Geometry

    private var notchWidth: CGFloat {
        guard let screen = NSScreen.main else { return 180 }
        if let left = screen.auxiliaryTopLeftArea?.width,
           let right = screen.auxiliaryTopRightArea?.width {
            return screen.frame.width - left - right
        }
        return 180
    }

    private var notchHeight: CGFloat {
        guard let screen = NSScreen.main else { return 37 }
        if screen.safeAreaInsets.top > 0 { return screen.safeAreaInsets.top }
        return NSApplication.shared.mainMenu?.menuBarHeight ?? NSStatusBar.system.thickness
    }

    // MARK: - Layout Constants

    private let recordingSideExpansion: CGFloat = 90
    private let transcriptSideExpansion: CGFloat = 110
    private let activeHeightBonus: CGFloat = 6
    private let transcriptPanelHeight: CGFloat = 57

    private var mainRowHeight: CGFloat { notchHeight + activeHeightBonus }

    // MARK: - Pill Dimensions

    private var pillWidth: CGFloat {
        switch displayState {
        case .collapsed: return notchWidth
        case .active:    return notchWidth + recordingSideExpansion * 2
        case .liveText:  return notchWidth + transcriptSideExpansion * 2
        }
    }

    private var pillHeight: CGFloat {
        switch displayState {
        case .collapsed: return 0
        case .active:    return mainRowHeight
        case .liveText:  return mainRowHeight + transcriptPanelHeight
        }
    }

    private var sideExpansion: CGFloat {
        displayState == .liveText ? transcriptSideExpansion : recordingSideExpansion
    }

    // MARK: - Animation

    private let expandAnimation = Animation.spring(response: 0.42, dampingFraction: 0.80)
    private let collapseAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0)

    private var pillAnimation: Animation {
        displayState == .collapsed ? collapseAnimation : expandAnimation
    }

    // MARK: - Body

    var body: some View {
        if windowManager.isVisible {
            GeometryReader { geo in
                pill.position(x: geo.size.width / 2, y: pillHeight / 2)
            }
            .animation(pillAnimation, value: displayState)
        }
    }

    // MARK: - Pill

    private var pill: some View {
        VStack(spacing: 0) {
            mainRow
            liveTextPanel
        }
        .frame(width: pillWidth, height: pillHeight)
        .background(Color.black)
        .clipShape(
            NotchShape(
                topCornerRadius: displayState == .liveText ? 12 : 8,
                bottomCornerRadius: displayState == .liveText ? 22 : 16
            )
        )
    }

    // MARK: - Main Row

    private var mainRow: some View {
        ZStack {
            Color.clear

            HStack(spacing: 10) {
                RecorderPromptButton(activePopover: $activePopover, buttonSize: 20, padding: EdgeInsets())
                RecorderPowerModeButton(activePopover: $activePopover, buttonSize: 20, padding: EdgeInsets())
                Spacer(minLength: 0)
            }
            .padding(.leading, displayState == .liveText ? 18 : 14)
            .frame(width: sideExpansion)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(displayState != .collapsed ? 1 : 0)
            .animation(
                displayState != .collapsed ? expandAnimation.delay(0.09) : collapseAnimation,
                value: displayState
            )

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                RecorderStatusDisplay(
                    currentState: stateProvider.recordingState,
                    audioMeter: recorder.audioMeter,
                    menuBarHeight: notchHeight
                )
            }
            .padding(.trailing, displayState == .liveText ? 18 : 14)
            .frame(width: sideExpansion)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(displayState != .collapsed ? 1 : 0)
            .animation(
                displayState != .collapsed ? expandAnimation.delay(0.09) : collapseAnimation,
                value: displayState
            )
        }
        .frame(height: mainRowHeight)
    }

    // MARK: - Live Text Panel

    private var liveTextPanel: some View {
        VStack(spacing: 0) {
            if displayState == .liveText {
                Divider().background(Color.white.opacity(0.15))
                LiveTranscriptView(text: stateProvider.partialTranscript)
                    .padding(.horizontal, 8)
            }
        }
        .frame(height: displayState == .liveText ? transcriptPanelHeight : 0)
        .clipped()
    }
}
