import SwiftUI
import AppKit

class MiniWindowManager: ObservableObject {
    @Published var isVisible = false
    private var windowController: NSWindowController?
    private var miniPanel: MiniRecorderPanel?

    // Type-erased view factory stored as closure
    private let makeView: (MiniWindowManager) -> AnyView

    init(engine: VoiceInkEngine, recorder: Recorder) {
        guard let enhancementService = engine.enhancementService else {
            preconditionFailure("VoiceInkEngine.enhancementService must be non-nil when creating MiniWindowManager")
        }
        self.makeView = { manager in
            AnyView(
                MiniRecorderView(stateProvider: engine, recorder: recorder)
                    .environmentObject(manager)
                    .environmentObject(enhancementService)
            )
        }
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

    func show() {
        if isVisible { return }

        let activeScreen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        initializeWindow(screen: activeScreen)
        self.isVisible = true
        miniPanel?.show()
    }

    func hide() {
        guard isVisible else { return }
        self.isVisible = false
        self.miniPanel?.hide { [weak self] in
            guard let self = self else { return }
            self.deinitializeWindow()
        }
    }

    private func initializeWindow(screen: NSScreen) {
        deinitializeWindow()

        let metrics = MiniRecorderPanel.calculateWindowMetrics()
        let panel = MiniRecorderPanel(contentRect: metrics)

        let miniRecorderView = makeView(self)
        let hostingController = NSHostingController(rootView: miniRecorderView)
        panel.contentView = hostingController.view

        self.miniPanel = panel
        self.windowController = NSWindowController(window: panel)

        panel.orderFrontRegardless()
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
