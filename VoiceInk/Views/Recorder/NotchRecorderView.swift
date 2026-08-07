import SwiftUI

struct NotchRecorderView<S: RecorderStateProvider & Observable>: View {
    var stateProvider: S
    var recorder: Recorder
    var assistantSession: AssistantSession
    let onRecordButtonTapped: () -> Void
    let onCloseTapped: () -> Void
    let onAssistantFollowUp: (String) -> Void
    @AppStorage(RecorderDisplaySettingsKeys.showLiveTranscript) private var showLiveTranscript = true
    @State private var healthMonitor = RecorderInputHealthMonitor()
    @State private var densityJudge = RecorderDensityJudge()

    // MARK: - Display State

    private var presentation: RecorderPresentation {
        RecorderPresentation(
            recordingState: stateProvider.recordingState,
            partialTranscript: stateProvider.partialTranscript,
            showLiveTranscript: showLiveTranscript,
            isAssistantVisible: assistantSession.isVisible,
            isAssistantBusy: assistantSession.isBusy
        )
    }

    private var displayState: RecorderDisplayState {
        presentation.displayState
    }

    // MARK: - Screen Geometry

    private var notchWidth: CGFloat {
        guard let screen = NSScreen.main else { return 180 }
        if let left = screen.auxiliaryTopLeftArea?.width,
            let right = screen.auxiliaryTopRightArea?.width
        {
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
    private let assistantSideExpansion: CGFloat = 230
    private let activeHeightBonus: CGFloat = 6
    private let transcriptPanelHeight: CGFloat = 57
    private let assistantPanelHeight: CGFloat = 320

    private var mainRowHeight: CGFloat { notchHeight + activeHeightBonus }

    // MARK: - Pill Dimensions

    private var pillWidth: CGFloat {
        notchWidth + sideExpansion * 2
    }

    private let signalStripHeight: CGFloat = 26

    private var pillHeight: CGFloat {
        let strip = showsSignalStrip ? signalStripHeight : 0
        switch displayState {
        case .collapsed: return 0
        case .active: return mainRowHeight + strip
        case .liveText: return mainRowHeight + strip + transcriptPanelHeight
        case .assistant: return mainRowHeight + assistantPanelHeight
        }
    }

    /// Width grammar — one expansion per width class, so a given width always means one thing.
    /// Collapsed contributes nothing, letting the pill shrink back to exactly the notch.
    private var sideExpansion: CGFloat {
        switch presentation.widthClass {
        case .compact: return 0
        case .standard: return recordingSideExpansion
        case .wide: return transcriptSideExpansion
        case .conversation: return assistantSideExpansion
        }
    }

    /// Width the side controls are laid out in. Held at the recording expansion even while
    /// collapsed so the buttons do not squash to zero on the way out — only the pill animates.
    private var controlColumnWidth: CGFloat {
        max(sideExpansion, recordingSideExpansion)
    }

    private var sideEdgePadding: CGFloat {
        displayState == .liveText || displayState == .assistant ? 20 : 16
    }

    private var shouldShowCloseButton: Bool {
        presentation.shouldShowCloseButton
    }

    private var liveAssistantFollowUpText: String {
        presentation.assistantFollowUpText
    }

    // MARK: - Animation

    private let expandAnimation = AppTheme.Motion.panelExpand
    private let collapseAnimation = AppTheme.Motion.panelCollapse

    private var pillAnimation: Animation {
        displayState == .collapsed ? collapseAnimation : expandAnimation
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            pill.position(x: geo.size.width / 2, y: pillHeight / 2)
        }
        .animation(pillAnimation, value: displayState)
        .animation(AppTheme.Motion.standard, value: showsSignalStrip)
        .task(id: presentation.recordingState) {
            guard presentation.recordingState == .recording else {
                healthMonitor.reset()
                densityJudge.endTake()
                return
            }
            RecorderModeFamiliarity.recordUse(of: ModeManager.shared.currentEffectiveConfiguration?.id)

            while !Task.isCancelled {
                healthMonitor.ingest(recorder.audioMeterSnapshot())
                judgeDensity()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    // MARK: - Pill

    private var pill: some View {
        VStack(spacing: 0) {
            mainRow
            signalStrip
            liveTextPanel
            assistantPanel
        }
        .frame(width: pillWidth, height: pillHeight)
        .background(
            NotchRecorderChrome(
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: bottomCornerRadius,
                rimState: presentation.rimState
            )
        )
        .clipShape(
            NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius)
        )
    }

    private var topCornerRadius: CGFloat {
        displayState == .liveText ? 12 : 8
    }

    private var bottomCornerRadius: CGFloat {
        displayState == .liveText || displayState == .assistant ? 22 : 16
    }

    // MARK: - Main Row

    private var mainRow: some View {
        ZStack {
            Color.clear

            HStack(spacing: 14) {
                if shouldShowCloseButton {
                    RecorderCloseButton(action: onCloseTapped)
                } else {
                    RecorderRecordButton(
                        recordingState: stateProvider.recordingState,
                        action: onRecordButtonTapped
                    )
                }
                RecorderModeButton(buttonSize: 20, padding: EdgeInsets())
                Spacer(minLength: 0)
            }
            .padding(.leading, sideEdgePadding)
            .frame(width: controlColumnWidth)
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
                    audioMeterProvider: recorder.audioMeterSnapshot,
                    menuBarHeight: notchHeight
                )
            }
            .padding(.trailing, sideEdgePadding)
            .frame(width: controlColumnWidth)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(displayState != .collapsed ? 1 : 0)
            .animation(
                displayState != .collapsed ? expandAnimation.delay(0.09) : collapseAnimation,
                value: displayState
            )
        }
        .frame(height: mainRowHeight)
    }

    /// The strip earns its space only when it has something non-obvious to report.
    private var showsSignalStrip: Bool {
        presentation.recordingState == .recording
            && densityJudge.density >= .standard
            && RecorderSignalStrip.shouldRender(
                health: healthMonitor.health,
                context: stateProvider.contextSummary
            )
    }

    private func judgeDensity() {
        let mode = ModeManager.shared.currentEffectiveConfiguration
        densityJudge.evaluate(
            .init(
                isRecording: presentation.recordingState == .recording,
                hasHealthProblem: healthMonitor.health.isProblem,
                contextIsEmpty: stateProvider.contextSummary.isEmpty,
                isRealtimeTranscriptionEnabled: mode?.isRealtimeTranscriptionEnabled ?? false,
                showLiveTranscript: showLiveTranscript,
                isUnfamiliarMode: RecorderModeFamiliarity.isUnfamiliar(mode?.id),
                deviceChangedDuringTake: false
            )
        )
    }

    @ViewBuilder
    private var signalStrip: some View {
        if showsSignalStrip {
            RecorderSignalStrip(
                health: healthMonitor.health,
                context: stateProvider.contextSummary,
                deviceName: AudioDeviceManager.shared.currentInputDeviceName
            )
            .frame(width: pillWidth)
        }
    }

    // MARK: - Live Text Panel

    private var liveTextPanel: some View {
        VStack(spacing: 0) {
            if displayState == .liveText {
                Divider().background(AppTheme.Recorder.separator)
                LiveTranscriptView(text: stateProvider.partialTranscript)
                    .padding(.horizontal, 8)
            }
        }
        .frame(height: displayState == .liveText ? transcriptPanelHeight : 0)
        .clipped()
    }

    private var assistantPanel: some View {
        VStack(spacing: 0) {
            if displayState == .assistant {
                Divider().background(AppTheme.Recorder.separator)
                AssistantPanelView(
                    session: assistantSession,
                    liveFollowUpText: liveAssistantFollowUpText,
                    onSend: onAssistantFollowUp
                )
            }
        }
        .frame(height: displayState == .assistant ? assistantPanelHeight : 0)
        .clipped()
    }
}
