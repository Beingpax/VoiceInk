import SwiftUI
import AppKit

class MiniWindowManager: ObservableObject {
    @Published var isVisible = false
    private var windowController: NSWindowController?
    private var miniPanel: MiniRecorderPanel?
    private let whisperState: WhisperState
    private let recorder: Recorder
    
    init(whisperState: WhisperState, recorder: Recorder) {
        self.whisperState = whisperState
        self.recorder = recorder
        setupNotifications()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHideNotification),
            name: NSNotification.Name("HideMiniRecorder"),
            object: nil
        )
    }
    
    @objc private func handleHideNotification() {
        hide()
    }
    func show(on screen: NSScreen? = nil) {
        if isVisible { return }

        if miniPanel == nil {
            initializeWindow(on: screen)
        }
        self.isVisible = true
        miniPanel?.show(on: screen)
    }

    func hide() {
        guard isVisible else { return }

        self.isVisible = false
        miniPanel?.orderOut(nil)
    }

    private func initializeWindow(on screen: NSScreen? = nil) {
        let metrics = MiniRecorderPanel.calculateWindowMetrics(for: screen)
        let panel = MiniRecorderPanel(contentRect: metrics)

        let miniRecorderView = MiniRecorderView(whisperState: whisperState, recorder: recorder)
            .environmentObject(self)
            .environmentObject(whisperState.enhancementService!)

        let hostingController = NSHostingController(rootView: miniRecorderView)
        panel.contentView = hostingController.view

        self.miniPanel = panel
        self.windowController = NSWindowController(window: panel)
    }

    private func deinitializeWindow() {
        miniPanel?.orderOut(nil)
        windowController?.close()
        windowController = nil
        miniPanel = nil
    }
    
    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }
} 
