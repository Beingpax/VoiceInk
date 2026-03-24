import SwiftUI
import AppKit

@MainActor
class VoiceLoopWindowManager: ObservableObject {
    @Published var isVisible = false

    private var windowController: NSWindowController?
    private var panel: VoiceLoopPanel?
    private let manager: VoiceConversationManager

    init(manager: VoiceConversationManager) {
        self.manager = manager
    }

    func show() {
        if isVisible { return }

        if panel == nil {
            initializeWindow()
        }

        isVisible = true
        panel?.show()
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        panel?.orderOut(nil)
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    private func initializeWindow() {
        deinitializeWindow()

        let metrics = VoiceLoopPanel.calculateWindowMetrics()
        let newPanel = VoiceLoopPanel(contentRect: metrics)

        let hudView = VoiceLoopHUD(manager: manager)
        let hostingController = NSHostingController(rootView: hudView)
        newPanel.contentView = hostingController.view

        self.panel = newPanel
        self.windowController = NSWindowController(window: newPanel)

        newPanel.orderFrontRegardless()
    }

    private func deinitializeWindow() {
        panel?.orderOut(nil)
        windowController?.close()
        windowController = nil
        panel = nil
    }
}
