import SwiftUI
import AppKit

@MainActor
class MiniWindowManager {
    private var windowController: NSWindowController?
    private var panel: MiniRecorderPanel?

    private let makeView: () -> AnyView

    init(
        engine: VoiceInkEngine,
        recorder: Recorder,
        assistantSession: AssistantSession,
        onRecordButtonTapped: @escaping () -> Void,
        onCloseTapped: @escaping () -> Void,
        onAssistantFollowUp: @escaping (String) -> Void
    ) {
        self.makeView = {
            AnyView(
                MiniRecorderView(
                    stateProvider: engine,
                    recorder: recorder,
                    assistantSession: assistantSession,
                    onRecordButtonTapped: onRecordButtonTapped,
                    onCloseTapped: onCloseTapped,
                    onAssistantFollowUp: onAssistantFollowUp
                )
            )
        }
    }

    func show() {
        if panel == nil { initializeWindow() }
        panel?.show()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func destroyWindow() {
        deinitializeWindow()
    }

    private func initializeWindow() {
        deinitializeWindow()
        let metrics = MiniRecorderPanel.calculateWindowMetrics()
        let newPanel = MiniRecorderPanel(contentRect: metrics)
        let view = makeView()
        let hostingController = NSHostingController(rootView: view)
        newPanel.contentView = hostingController.view
        panel = newPanel
        windowController = NSWindowController(window: newPanel)
    }

    private func deinitializeWindow() {
        panel?.orderOut(nil)
        windowController?.close()
        windowController = nil
        panel = nil
    }
}
