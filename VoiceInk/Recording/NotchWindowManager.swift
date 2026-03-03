import SwiftUI
import AppKit

@MainActor
class NotchWindowManager: ObservableObject {
    @Published var isVisible = false
    private var windowController: NSWindowController?
    var notchPanel: NotchRecorderPanel?

    // Type-erased references stored as closures to avoid generic class limitations
    private let makeView: (NotchWindowManager) -> AnyView
    private let enhancementService: AIEnhancementService

    init(engine: VoiceInkEngine, recorder: Recorder) {
        guard let enhancementService = engine.enhancementService else {
            preconditionFailure("VoiceInkEngine.enhancementService must be non-nil when creating NotchWindowManager")
        }
        self.enhancementService = enhancementService
        self.makeView = { manager in
            AnyView(
                NotchRecorderView(stateProvider: engine, recorder: recorder)
                    .environmentObject(manager)
                    .environmentObject(enhancementService)
            )
        }
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

        let activeScreen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        initializeWindow(screen: activeScreen)
        self.isVisible = true
        notchPanel?.show()
    }

    func hide() {
        guard isVisible else { return }
        self.isVisible = false
        self.notchPanel?.hide { [weak self] in
            guard let self = self else { return }
            self.deinitializeWindow()
        }
    }

    private func initializeWindow(screen: NSScreen) {
        deinitializeWindow()

        let metrics = NotchRecorderPanel.calculateWindowMetrics()
        let panel = NotchRecorderPanel(contentRect: metrics.frame)

        let notchRecorderView = makeView(self)
        let hostingController = NotchRecorderHostingController(rootView: notchRecorderView)
        panel.contentView = hostingController.view

        self.notchPanel = panel
        self.windowController = NSWindowController(window: panel)

        panel.orderFrontRegardless()
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
