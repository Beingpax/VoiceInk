import SwiftUI
import AppKit

// MARK: - Recorder Style
enum RecorderStyle: String {
    case mini
    case notch

    var hideNotificationName: String {
        switch self {
        case .mini: return "HideMiniRecorder"
        case .notch: return "HideNotchRecorder"
        }
    }
}

// MARK: - Unified Recorder Window Manager
@MainActor
class RecorderWindowManager: ObservableObject {
    @Published var isVisible = false

    private var windowController: NSWindowController?
    private var panel: NSPanel?
    private let whisperState: WhisperState
    private let recorder: Recorder
    private let style: RecorderStyle

    init(whisperState: WhisperState, recorder: Recorder, style: RecorderStyle) {
        self.whisperState = whisperState
        self.recorder = recorder
        self.style = style
        setupNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHideNotification),
            name: NSNotification.Name(style.hideNotificationName),
            object: nil
        )
    }

    @objc private func handleHideNotification() {
        hide()
    }

    func show() {
        if isVisible { return }

        let activeScreen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        initializeWindow(screen: activeScreen)
        self.isVisible = true

        switch style {
        case .mini:
            (panel as? MiniRecorderPanel)?.show()
        case .notch:
            (panel as? NotchRecorderPanel)?.show()
        }
    }

    func hide() {
        guard isVisible else { return }

        self.isVisible = false

        switch style {
        case .mini:
            (panel as? MiniRecorderPanel)?.hide { [weak self] in
                self?.deinitializeWindow()
            }
        case .notch:
            (panel as? NotchRecorderPanel)?.hide { [weak self] in
                self?.deinitializeWindow()
            }
        }
    }

    private func initializeWindow(screen: NSScreen) {
        deinitializeWindow()

        switch style {
        case .mini:
            initializeMiniWindow()
        case .notch:
            initializeNotchWindow()
        }

        panel?.orderFrontRegardless()
    }

    private func initializeMiniWindow() {
        let metrics = MiniRecorderPanel.calculateWindowMetrics()
        let miniPanel = MiniRecorderPanel(contentRect: metrics)

        let miniRecorderView = MiniRecorderView(whisperState: whisperState, recorder: recorder)
            .environmentObject(self)
            .environmentObject(whisperState.enhancementService!)

        let hostingController = NSHostingController(rootView: miniRecorderView)
        miniPanel.contentView = hostingController.view

        self.panel = miniPanel
        self.windowController = NSWindowController(window: miniPanel)
    }

    private func initializeNotchWindow() {
        let metrics = NotchRecorderPanel.calculateWindowMetrics()
        let notchPanel = NotchRecorderPanel(contentRect: metrics.frame)

        let notchRecorderView = NotchRecorderView(whisperState: whisperState, recorder: recorder)
            .environmentObject(self)
            .environmentObject(whisperState.enhancementService!)

        let hostingController = NotchRecorderHostingController(rootView: notchRecorderView)
        notchPanel.contentView = hostingController.view

        self.panel = notchPanel
        self.windowController = NSWindowController(window: notchPanel)
    }

    private func deinitializeWindow() {
        panel?.orderOut(nil)
        windowController?.close()
        windowController = nil
        panel = nil
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }
}
