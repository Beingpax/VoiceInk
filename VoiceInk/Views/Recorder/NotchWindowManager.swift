import SwiftUI
import AppKit

@MainActor
class NotchWindowManager: ObservableObject {
    @Published var isVisible = false
    private var windowController: NSWindowController?
     var notchPanel: NotchRecorderPanel?
    private let whisperState: WhisperState
    private let recorder: Recorder

    init(whisperState: WhisperState, recorder: Recorder) {
        self.whisperState = whisperState
        self.recorder = recorder

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHideNotification),
            name: NSNotification.Name("HideNotchRecorder"),
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleHideNotification() {
        hide()
    }
    
    func show() {
        if isVisible { return }

        if notchPanel == nil {
            initializeWindow()
        }
        self.isVisible = true
        notchPanel?.show()
    }

    func hide() {
        guard isVisible else { return }

        self.isVisible = false
        notchPanel?.orderOut(nil)
    }

    private func initializeWindow() {
        let metrics = NotchRecorderPanel.calculateWindowMetrics()
        let panel = NotchRecorderPanel(contentRect: metrics.frame)

        let notchRecorderView = NotchRecorderView(whisperState: whisperState, recorder: recorder)
            .environmentObject(self)
            .environmentObject(whisperState.enhancementService!)

        let hostingController = NotchRecorderHostingController(rootView: notchRecorderView)
        panel.contentView = hostingController.view

        self.notchPanel = panel
        self.windowController = NSWindowController(window: panel)
    }

    private func deinitializeWindow() {
        notchPanel?.orderOut(nil)
        windowController?.close()
        windowController = nil
        notchPanel = nil
    }
    
    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }
} 
